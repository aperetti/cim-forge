import 'package:cim_forge/features/model/element.dart';
import 'package:cim_forge/shared/rdf/rdf_xml_reader.dart';

/// Parsed object graph — every CIM [CimElement] indexed by id, plus the
/// original source for surgical patches.
class ObjectGraph {
  ObjectGraph._({required this.source, required Map<String, CimElement> byId})
    : _byId = byId;

  /// Parses [source] as CIM RDF/XML and builds an [ObjectGraph]. Elements
  /// without an id (no `rdf:ID` and no `rdf:about`) are skipped — they
  /// cannot participate in associations or be addressed for edits.
  factory ObjectGraph.parse(String source) {
    final events = readRdfXml(source).toList();
    final byId = <String, CimElement>{};

    final stack = <_Frame>[];

    for (final event in events) {
      if (event is StartElementEvent) {
        if (_isRdfWrapper(event.name)) {
          stack.add(_Frame.wrapper(event));
          continue;
        }

        // Top-level CIM element (child of rdf:RDF).
        if (stack.length == 1 && _isRdfWrapper(stack.last.name)) {
          final id = _extractId(event);
          if (id != null) {
            stack.add(_Frame.element(event, id));
          } else {
            stack.add(_Frame.ignored(event));
          }
          continue;
        }

        // Property of the current element (child of a top-level element).
        if (stack.length == 2 && stack.last.kind == _FrameKind.element) {
          if (event.isSelfClosing) {
            // No matching EndElement will arrive — attach inline.
            _attachSelfClosingProperty(stack.last, event);
          } else {
            stack.add(_Frame.property(event));
          }
          continue;
        }

        // Anything deeper is treated as ignored content (CIM RDF/XML in our
        // dialect doesn't nest deeper than property -> text). Self-closing
        // ignored elements must not be pushed either.
        if (!event.isSelfClosing) stack.add(_Frame.ignored(event));
      } else if (event is EndElementEvent) {
        if (stack.isEmpty) continue;
        final frame = stack.removeLast();
        if (frame.kind == _FrameKind.element) {
          final el = _buildElement(frame, event, source);
          byId[el.id] = el;
        } else if (frame.kind == _FrameKind.property) {
          // Attach the property to its parent element frame.
          if (stack.isNotEmpty && stack.last.kind == _FrameKind.element) {
            _attachProperty(stack.last, frame, event, source);
          }
        }
      } else if (event is TextEvent) {
        if (stack.isNotEmpty && stack.last.kind == _FrameKind.property) {
          stack.last.textSpan ??= event.span;
          stack.last.textValue =
              (stack.last.textValue ?? '') + event.value;
        }
      }
    }

    return ObjectGraph._(source: source, byId: byId);
  }

  /// The original XML source. Held so that surgical patches can be applied
  /// against the exact text the spans were computed against.
  final String source;

  final Map<String, CimElement> _byId;

  Iterable<CimElement> get elements => _byId.values;
  int get elementCount => _byId.length;

  CimElement? elementById(String id) => _byId[id];
}

bool _isRdfWrapper(String name) => name == 'rdf:RDF';

String? _extractId(StartElementEvent e) {
  for (final attr in e.attributes) {
    if (attr.name == 'rdf:ID') return attr.value;
    if (attr.name == 'rdf:about') {
      final v = attr.value;
      return v.startsWith('#') ? v.substring(1) : v;
    }
  }
  return null;
}

SourceSpan _idAttributeSpan(StartElementEvent e) {
  for (final attr in e.attributes) {
    if (attr.name == 'rdf:ID' || attr.name == 'rdf:about') return attr.span;
  }
  // Should not happen if caller checked _extractId first.
  return e.span;
}

String _stripPrefix(String full) {
  final colon = full.indexOf(':');
  return colon >= 0 ? full.substring(colon + 1) : full;
}

void _attachProperty(
  _Frame elementFrame,
  _Frame propertyFrame,
  EndElementEvent endEvent,
  String source,
) {
  final fullElementSpan = SourceSpan(
    propertyFrame.start.span.start,
    endEvent.span.stop,
  );
  final propertyName = _stripPrefix(propertyFrame.name);

  // rdf:resource attribute → association
  for (final attr in propertyFrame.start.attributes) {
    if (attr.name == 'rdf:resource') {
      final target = attr.value.startsWith('#')
          ? attr.value.substring(1)
          : attr.value;
      elementFrame.associations.add(
        ElementAssociation(
          name: propertyName,
          targetId: target,
          elementSpan: fullElementSpan,
          targetSpan: attr.span,
        ),
      );
      return;
    }
  }

  // Otherwise scalar attribute with text content.
  final text = propertyFrame.textValue ?? '';
  final textSpan =
      propertyFrame.textSpan ??
      SourceSpan(
        propertyFrame.start.span.stop,
        propertyFrame.start.span.stop,
      );
  elementFrame.attributes.add(
    ElementAttribute(
      name: propertyName,
      value: text,
      elementSpan: fullElementSpan,
      textSpan: textSpan,
    ),
  );
}

void _attachSelfClosingProperty(
  _Frame elementFrame,
  StartElementEvent start,
) {
  final propertyName = _stripPrefix(start.name);
  for (final attr in start.attributes) {
    if (attr.name == 'rdf:resource') {
      final target = attr.value.startsWith('#')
          ? attr.value.substring(1)
          : attr.value;
      elementFrame.associations.add(
        ElementAssociation(
          name: propertyName,
          targetId: target,
          elementSpan: start.span,
          targetSpan: attr.span,
        ),
      );
      return;
    }
  }
  // Self-closing without rdf:resource = empty scalar.
  elementFrame.attributes.add(
    ElementAttribute(
      name: propertyName,
      value: '',
      elementSpan: start.span,
      textSpan: SourceSpan(start.span.stop, start.span.stop),
    ),
  );
}

CimElement _buildElement(_Frame frame, EndElementEvent end, String source) {
  return CimElement(
    id: frame.id!,
    className: _stripPrefix(frame.name),
    headerSpan: frame.start.span,
    closingSpan: frame.start.isSelfClosing ? null : end.span,
    idAttributeSpan: _idAttributeSpan(frame.start),
    attributes: frame.attributes,
    associations: frame.associations,
  );
}

enum _FrameKind { wrapper, element, property, ignored }

class _Frame {
  _Frame.wrapper(this.start)
    : kind = _FrameKind.wrapper,
      id = null,
      attributes = const [],
      associations = const [];

  _Frame.element(this.start, this.id)
    : kind = _FrameKind.element,
      attributes = [],
      associations = [];

  _Frame.property(this.start)
    : kind = _FrameKind.property,
      id = null,
      attributes = const [],
      associations = const [];

  _Frame.ignored(this.start)
    : kind = _FrameKind.ignored,
      id = null,
      attributes = const [],
      associations = const [];

  final StartElementEvent start;
  final _FrameKind kind;
  final String? id;
  final List<ElementAttribute> attributes;
  final List<ElementAssociation> associations;

  String get name => start.name;

  SourceSpan? textSpan;
  String? textValue;
}
