import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:cim_forge/shared/rdf/rdf_xml_reader.dart';

/// Loads a CIM RDF Schema (RDFS + the IEC `cims:` extensions) and builds a
/// [Metamodel]. The loader is profile-agnostic (FR-1.2) — no class names are
/// compiled in; only RDFS/cims conventions are interpreted.
class SchemaLoader {
  /// Parse [rdfsSource] and return the corresponding [Metamodel].
  static Metamodel load(String rdfsSource) {
    final classes = <String, _ClassBuilder>{};
    final enumerations = <String, List<String>>{};
    final propertyByName = <String, _PropertyBuilder>{};
    final classMembers = <String, List<String>>{}; // class -> enum members

    _ClassBuilder classFor(String name) =>
        classes.putIfAbsent(name, () => _ClassBuilder(name: name));

    String? currentSubject;
    _SubjectKind? currentKind;

    final events = readRdfXml(rdfsSource).toList();

    // First pass: identify subjects (rdfs:Class, rdf:Property,
    // rdf:Description), capture parent/domain/range/multiplicity, and
    // collect enum members. We track the "current subject" — the innermost
    // resource being described.
    String? lastDomain;
    String? lastRange;
    Cardinality? lastMultiplicity;

    for (final e in events) {
      if (e is StartElementEvent) {
        final name = e.name;
        if (_isElementName(name, 'rdfs', 'Class')) {
          currentSubject = _attrLocalName(e, 'rdf', 'about');
          currentKind = _SubjectKind.cimClass;
          if (currentSubject != null) classFor(currentSubject);
        } else if (_isElementName(name, 'rdf', 'Property')) {
          currentSubject = _attrLocalName(e, 'rdf', 'about');
          currentKind = _SubjectKind.property;
          lastDomain = null;
          lastRange = null;
          lastMultiplicity = null;
        } else if (_isElementName(name, 'rdf', 'Description')) {
          currentSubject = _attrLocalName(e, 'rdf', 'about');
          currentKind = _SubjectKind.description;
        } else if (currentKind == _SubjectKind.cimClass &&
            _isElementName(name, 'rdfs', 'subClassOf')) {
          final parent = _attrLocalName(e, 'rdf', 'resource');
          if (currentSubject != null && parent != null) {
            classFor(currentSubject).parent = parent;
          }
        } else if (currentKind == _SubjectKind.cimClass &&
            _isElementName(name, 'cims', 'stereotype')) {
          // Captured in the text event that follows. Nothing to do here.
        } else if (currentKind == _SubjectKind.property &&
            _isElementName(name, 'rdfs', 'domain')) {
          lastDomain = _attrLocalName(e, 'rdf', 'resource');
        } else if (currentKind == _SubjectKind.property &&
            _isElementName(name, 'rdfs', 'range')) {
          lastRange = _attrLocalName(e, 'rdf', 'resource');
        } else if (currentKind == _SubjectKind.property &&
            _isElementName(name, 'cims', 'multiplicity')) {
          final mult = _attrLocalName(e, 'rdf', 'resource');
          lastMultiplicity = _parseMultiplicity(mult);
        } else if (currentKind == _SubjectKind.description &&
            _isElementName(name, 'rdf', 'type')) {
          final type = _attrLocalName(e, 'rdf', 'resource');
          final subject = currentSubject;
          if (subject != null && type != null) {
            // Treat the description as an enum member of `type`.
            final dot = subject.indexOf('.');
            final member =
                dot >= 0 ? subject.substring(dot + 1) : subject;
            classMembers.putIfAbsent(type, () => []).add(member);
          }
        }
      } else if (e is EndElementEvent) {
        if (_isElementName(e.name, 'rdfs', 'Class') ||
            _isElementName(e.name, 'rdf', 'Property') ||
            _isElementName(e.name, 'rdf', 'Description')) {
          final subject = currentSubject;
          final domain = lastDomain;
          if (currentKind == _SubjectKind.property &&
              subject != null &&
              domain != null) {
            propertyByName[subject] = _PropertyBuilder(
              name: subject,
              domain: domain,
              range: lastRange ?? 'String',
              cardinality: lastMultiplicity ?? Cardinality.optional,
            );
          }
          currentSubject = null;
          currentKind = null;
          lastDomain = null;
          lastRange = null;
          lastMultiplicity = null;
        }
      }
    }

    // Resolve which classes are enumerations (have stereotype "Enumeration"
    // OR appear as the `rdf:type` of any description).
    final declaredEnums = <String>{};
    for (final cls in classes.values) {
      if (cls.stereotype == 'Enumeration') declaredEnums.add(cls.name);
    }
    declaredEnums.addAll(classMembers.keys);

    // Build enumerations from members.
    for (final enumName in declaredEnums) {
      final members = classMembers[enumName] ?? const <String>[];
      enumerations[enumName] = members;
    }

    // Wire properties into their owning classes — distinguishing attributes
    // (range = primitive / enum) from associations (range = another class).
    for (final prop in propertyByName.values) {
      final cls = classes[prop.domain];
      if (cls == null) continue;
      final isAssociation = classes.containsKey(prop.range) &&
          !declaredEnums.contains(prop.range);
      final shortName = _propertyShortName(prop.name);
      if (isAssociation) {
        cls.associations.add(
          CimAssociation(
            name: shortName,
            targetClass: prop.range,
            cardinality: prop.cardinality,
          ),
        );
      } else {
        cls.attributes.add(
          CimAttribute(
            name: shortName,
            dataType: prop.range,
            cardinality: prop.cardinality,
          ),
        );
      }
    }

    final builtClasses = <String, CimClass>{
      for (final c in classes.values)
        c.name: CimClass(
          name: c.name,
          parent: c.parent,
          ownAttributes: List.unmodifiable(c.attributes),
          ownAssociations: List.unmodifiable(c.associations),
        ),
    };

    final builtEnums = <String, CimEnumeration>{
      for (final entry in enumerations.entries)
        entry.key: CimEnumeration(
          name: entry.key,
          members: List.unmodifiable(entry.value),
        ),
    };

    // Second pass: pull stereotype text for class builders (used above for
    // enum detection). We need to revisit events and read child text.
    _collectStereotypes(events, classes);

    // Re-evaluate enum membership now that stereotypes are populated, then
    // rewire any classes that turned out to be enums but had no
    // rdf:Descriptions seeded.
    for (final cls in classes.values) {
      if (cls.stereotype == 'Enumeration' &&
          !builtEnums.containsKey(cls.name)) {
        builtEnums[cls.name] = CimEnumeration(
          name: cls.name,
          members: const [],
        );
      }
    }

    return Metamodel(classes: builtClasses, enumerations: builtEnums);
  }
}

void _collectStereotypes(
  List<RdfXmlEvent> events,
  Map<String, _ClassBuilder> classes,
) {
  String? subject;
  var inStereotype = false;
  for (final e in events) {
    if (e is StartElementEvent) {
      if (_isElementName(e.name, 'rdfs', 'Class')) {
        subject = _attrLocalName(e, 'rdf', 'about');
      } else if (_isElementName(e.name, 'cims', 'stereotype')) {
        inStereotype = true;
      }
    } else if (e is TextEvent && inStereotype && subject != null) {
      final value = e.value.trim();
      if (value.isNotEmpty) classes[subject]?.stereotype = value;
    } else if (e is EndElementEvent) {
      if (_isElementName(e.name, 'cims', 'stereotype')) {
        inStereotype = false;
      } else if (_isElementName(e.name, 'rdfs', 'Class')) {
        subject = null;
      }
    }
  }
}

enum _SubjectKind { cimClass, property, description }

class _ClassBuilder {
  _ClassBuilder({required this.name});
  final String name;
  String? parent;
  String? stereotype;
  final List<CimAttribute> attributes = [];
  final List<CimAssociation> associations = [];
}

class _PropertyBuilder {
  _PropertyBuilder({
    required this.name,
    required this.domain,
    required this.range,
    required this.cardinality,
  });
  final String name;
  final String domain;
  final String range;
  final Cardinality cardinality;
}

bool _isElementName(String full, String prefix, String local) {
  // Match exactly `prefix:local`. We're intentionally strict on prefix to
  // keep the loader explicit about CIM RDFS conventions.
  return full == '$prefix:$local';
}

String? _attrLocalName(StartElementEvent e, String prefix, String name) {
  for (final a in e.attributes) {
    if (a.name == '$prefix:$name') {
      return _stripNamespace(a.value);
    }
  }
  return null;
}

/// Maps "cim:ClassName" / "http://iec.ch/.../CIM100#ClassName" / "#ClassName"
/// to the bare local name. CIM RDFS uses both prefix and full-URI forms.
String _stripNamespace(String raw) {
  if (raw.startsWith('#')) return raw.substring(1);
  final hash = raw.lastIndexOf('#');
  if (hash >= 0) return raw.substring(hash + 1);
  final colon = raw.indexOf(':');
  if (colon >= 0) {
    final after = raw.substring(colon + 1);
    // Don't strip a colon that's part of a URI scheme like http:
    if (!raw.startsWith('http') && !raw.startsWith('urn')) return after;
    return raw;
  }
  return raw;
}

String _propertyShortName(String full) {
  final dot = full.lastIndexOf('.');
  return dot >= 0 ? full.substring(dot + 1) : full;
}

Cardinality _parseMultiplicity(String? raw) {
  if (raw == null) return Cardinality.optional;
  // cims:M:0..1, cims:M:1..1, cims:M:0..n, cims:M:1..n
  final m = RegExp(r'M:(\d+)\.\.(\d+|n|\*)$').firstMatch(raw);
  if (m == null) return Cardinality.optional;
  final min = int.parse(m.group(1)!);
  final maxStr = m.group(2)!;
  final max = (maxStr == 'n' || maxStr == '*') ? -1 : int.parse(maxStr);
  return Cardinality(min: min, max: max);
}
