import 'package:cim_forge/features/model/element.dart';
import 'package:cim_forge/features/model/object_graph.dart';

/// User-triggered canonical reserialization of a CIM RDF/XML file (FR-4.3).
/// Emits:
///   - elements sorted by id alphabetically
///   - within each element, attributes alphabetical by short name, then
///     associations alphabetical by short name
///   - 2-space indentation, LF newlines
///   - `cim:` prefix for every CIM class / property
///
/// Use the [serialize] entry point. The gate property: parsing the output
/// must yield a graph equivalent to parsing the original input.
class CanonicalSerializer {
  const CanonicalSerializer({
    this.classPrefix = 'cim:',
    this.rdfNamespace = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
    this.cimNamespace = 'http://iec.ch/TC57/CIM100#',
  });

  /// Prefix prepended to every class / property local name on emission.
  final String classPrefix;
  final String rdfNamespace;
  final String cimNamespace;

  String serialize(ObjectGraph graph) {
    final ids = graph.elements.map((e) => e.id).toList()..sort();
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<rdf:RDF xmlns:rdf="$rdfNamespace"\n'
        '         xmlns:cim="$cimNamespace">',
      );
    for (final id in ids) {
      final element = graph.elementById(id);
      if (element == null) continue;
      _writeElement(buf, element);
    }
    buf.writeln('</rdf:RDF>');
    return buf.toString();
  }

  void _writeElement(StringBuffer buf, CimElement element) {
    final qualified = '$classPrefix${element.className}';
    final idAttr = _isFragmentId(element.id) ? 'rdf:ID' : 'rdf:about';
    buf.writeln('  <$qualified $idAttr="${_xmlAttr(element.id)}">');

    final attrs = [...element.attributes]
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final attr in attrs) {
      final qname = '$classPrefix${attr.name}';
      buf.writeln(
        '    <$qname>${_xmlText(attr.value)}</$qname>',
      );
    }

    final assocs = [...element.associations]
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final assoc in assocs) {
      final qname = '$classPrefix${assoc.name}';
      final ref = _isFragmentId(assoc.targetId)
          ? '#${assoc.targetId}'
          : assoc.targetId;
      buf.writeln(
        '    <$qname rdf:resource="${_xmlAttr(ref)}"/>',
      );
    }

    buf.writeln('  </$qualified>');
  }

  bool _isFragmentId(String id) =>
      !id.startsWith('urn:') &&
      !id.startsWith('http:') &&
      !id.startsWith('https:');

  String _xmlAttr(String value) =>
      value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

  String _xmlText(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
