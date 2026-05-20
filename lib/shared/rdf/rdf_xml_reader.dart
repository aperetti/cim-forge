import 'package:meta/meta.dart';
import 'package:xml/xml_events.dart';

/// A char-offset range into the source XML string. Half-open: `start <=
/// offset < stop`. Always non-null on events produced by [readRdfXml].
@immutable
class SourceSpan {
  const SourceSpan(this.start, this.stop);
  final int start;
  final int stop;

  int get length => stop - start;

  @override
  bool operator ==(Object other) =>
      other is SourceSpan && other.start == start && other.stop == stop;

  @override
  int get hashCode => Object.hash(start, stop);

  @override
  String toString() => 'SourceSpan($start, $stop)';
}

/// A parsed RDF/XML attribute together with its byte range in the source.
///
/// The `package:xml` event API does not carry per-attribute offsets, so we
/// recover them by rescanning the start element's own span — the TR-9.1
/// spike proves this is sufficient and reliable for surgical patching.
@immutable
class RdfXmlAttribute {
  const RdfXmlAttribute({
    required this.name,
    required this.value,
    required this.span,
  });
  final String name;
  final String value;
  final SourceSpan span;
}

/// Event types emitted by [readRdfXml]. We narrow `package:xml`'s event API
/// to the shape RDF/XML consumers need, with every span populated.
sealed class RdfXmlEvent {
  const RdfXmlEvent(this.span);
  final SourceSpan span;
}

class StartElementEvent extends RdfXmlEvent {
  const StartElementEvent({
    required this.name,
    required this.attributes,
    required this.isSelfClosing,
    required SourceSpan span,
  }) : super(span);

  final String name;
  final List<RdfXmlAttribute> attributes;
  final bool isSelfClosing;
}

class EndElementEvent extends RdfXmlEvent {
  const EndElementEvent({required this.name, required SourceSpan span})
    : super(span);
  final String name;
}

class TextEvent extends RdfXmlEvent {
  const TextEvent({required this.value, required SourceSpan span})
    : super(span);
  final String value;
}

class CommentEvent extends RdfXmlEvent {
  const CommentEvent({required this.value, required SourceSpan span})
    : super(span);
  final String value;
}

class ProcessingInstructionEvent extends RdfXmlEvent {
  const ProcessingInstructionEvent({
    required this.target,
    required this.text,
    required SourceSpan span,
  }) : super(span);
  final String target;
  final String text;
}

/// Stream RDF/XML events for [source] with every event's [SourceSpan]
/// populated. Self-closing elements emit a single [StartElementEvent] with
/// [StartElementEvent.isSelfClosing] true and no matching end event.
Iterable<RdfXmlEvent> readRdfXml(String source) sync* {
  for (final event in parseEvents(source, withLocation: true)) {
    final start = event.start;
    final stop = event.stop;
    if (start == null || stop == null) continue;
    final span = SourceSpan(start, stop);
    if (event is XmlStartElementEvent) {
      yield StartElementEvent(
        name: event.name,
        attributes: _attributesFromSpan(event, source, span),
        isSelfClosing: event.isSelfClosing,
        span: span,
      );
    } else if (event is XmlEndElementEvent) {
      yield EndElementEvent(name: event.name, span: span);
    } else if (event is XmlTextEvent) {
      yield TextEvent(value: event.value, span: span);
    } else if (event is XmlCDATAEvent) {
      yield TextEvent(value: event.value, span: span);
    } else if (event is XmlCommentEvent) {
      yield CommentEvent(value: event.value, span: span);
    } else if (event is XmlProcessingEvent) {
      yield ProcessingInstructionEvent(
        target: event.target,
        text: event.value,
        span: span,
      );
    }
  }
}

List<RdfXmlAttribute> _attributesFromSpan(
  XmlStartElementEvent event,
  String source,
  SourceSpan elementSpan,
) {
  if (event.attributes.isEmpty) return const [];
  final elementText = source.substring(elementSpan.start, elementSpan.stop);
  final out = <RdfXmlAttribute>[];
  var searchFrom = 0;
  for (final attr in event.attributes) {
    // Match `name="value"` or `name='value'`. The xml event API has already
    // unescaped the value, but the literal in source text uses the original
    // form, so build both candidates.
    final candidates = [
      '${attr.name}="${attr.value}"',
      "${attr.name}='${attr.value}'",
    ];
    var foundAt = -1;
    var foundLength = 0;
    for (final candidate in candidates) {
      final idx = elementText.indexOf(candidate, searchFrom);
      if (idx >= 0) {
        foundAt = idx;
        foundLength = candidate.length;
        break;
      }
    }
    if (foundAt < 0) {
      // Attribute may have entity-escaped value in the source. Fall back to
      // locating `name=` and bounding by the closing quote — keeps the span
      // valid for editing even if the literal isn't a string-equal match.
      final namePos = elementText.indexOf('${attr.name}=', searchFrom);
      if (namePos < 0) continue; // shouldn't happen on well-formed XML
      final quoteChar = elementText[namePos + attr.name.length + 1];
      final endQuote = elementText.indexOf(
        quoteChar,
        namePos + attr.name.length + 2,
      );
      if (endQuote < 0) continue;
      foundAt = namePos;
      foundLength = endQuote - namePos + 1;
    }
    final absStart = elementSpan.start + foundAt;
    final absStop = absStart + foundLength;
    out.add(
      RdfXmlAttribute(
        name: attr.name,
        value: attr.value,
        span: SourceSpan(absStart, absStop),
      ),
    );
    searchFrom = foundAt + foundLength;
  }
  return out;
}
