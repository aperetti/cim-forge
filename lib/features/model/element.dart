import 'package:cim_forge/shared/rdf/rdf_xml_reader.dart';
import 'package:meta/meta.dart';

/// A scalar attribute on a CIM element — name + literal text value, with
/// byte ranges that point back at the source XML.
@immutable
class ElementAttribute {
  const ElementAttribute({
    required this.name,
    required this.value,
    required this.elementSpan,
    required this.textSpan,
  });

  /// Full property name as it appears in the XML, e.g.
  /// `IdentifiedObject.name`. The prefix (`cim:`) is stripped.
  final String name;
  final String value;

  /// Span of the entire `<Class.attr>...</Class.attr>` element.
  final SourceSpan elementSpan;

  /// Span of just the text content (between the tags). For an edit, replace
  /// this range; the surrounding element stays untouched, preserving the
  /// formatting and any inline whitespace.
  final SourceSpan textSpan;

  /// Short property name — the suffix after the last dot, e.g. `name` for
  /// `IdentifiedObject.name`.
  String get shortName {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : name;
  }
}

/// An association on a CIM element — represented as a `rdf:resource` link to
/// another element by its id.
@immutable
class ElementAssociation {
  const ElementAssociation({
    required this.name,
    required this.targetId,
    required this.elementSpan,
    required this.targetSpan,
  });

  /// Full property name as it appears in the XML, e.g.
  /// `Equipment.EquipmentContainer`.
  final String name;

  /// Id of the target element (stripped of `#` prefix).
  final String targetId;

  /// Span of the entire `<Class.assoc .../>` element.
  final SourceSpan elementSpan;

  /// Span of the `rdf:resource="..."` attribute literal — for edits that
  /// retarget the association.
  final SourceSpan targetSpan;

  String get shortName {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : name;
  }
}

/// A CIM element in the parsed RDF/XML — uniquely identified by [id]
/// (rdf:ID or rdf:about value), tagged with its [className], and carrying
/// scalar [attributes] and outgoing [associations]. Every position in the
/// element is anchored in the source so surgical edits can be expressed
/// without reformatting the file.
class CimElement {
  CimElement({
    required this.id,
    required this.className,
    required this.headerSpan,
    required this.closingSpan,
    required this.idAttributeSpan,
    required List<ElementAttribute> attributes,
    required List<ElementAssociation> associations,
  }) : _attributes = attributes,
       _associations = associations;

  /// Identifier from `rdf:ID` (with `#` prefix implied) or `rdf:about`. The
  /// id is exactly the literal in the source, minus a leading `#`.
  final String id;

  /// Local class name (e.g. `ACLineSegment` — the `cim:` prefix stripped).
  final String className;

  /// Span of the opening tag, including its attributes.
  final SourceSpan headerSpan;

  /// Span of the closing tag (`</cim:Class>`) — null for self-closing
  /// elements (which are rare for typed elements but legal).
  final SourceSpan? closingSpan;

  /// Span of the literal `rdf:ID="..."` / `rdf:about="..."` attribute on
  /// the opening tag. Used for rename operations.
  final SourceSpan idAttributeSpan;

  final List<ElementAttribute> _attributes;
  final List<ElementAssociation> _associations;

  List<ElementAttribute> get attributes => List.unmodifiable(_attributes);
  List<ElementAssociation> get associations =>
      List.unmodifiable(_associations);

  /// Find an attribute by short name (e.g. `name`) or full name (e.g.
  /// `IdentifiedObject.name`). Returns null if not present.
  ElementAttribute? attribute(String name) {
    for (final a in _attributes) {
      if (a.name == name || a.shortName == name) return a;
    }
    return null;
  }

  /// Find an association by short name or full name.
  ElementAssociation? association(String name) {
    for (final a in _associations) {
      if (a.name == name || a.shortName == name) return a;
    }
    return null;
  }
}
