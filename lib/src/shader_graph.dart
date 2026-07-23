import 'dart:convert';
import 'dart:typed_data';

import 'math.dart';
import 'particles.dart';

enum GlintShaderValueType { scalar, vector2, vector3, vector4 }

enum GlintShaderNodeType {
  uv,
  time,
  worldPosition,
  worldNormal,
  viewDirection,
  baseTexture,
  constant,
  parameter,
  textureSample,
  add,
  subtract,
  multiply,
  divide,
  mix,
  power,
  sine,
  cosine,
  absolute,
  oneMinus,
  saturate,
  normalize,
  dot,
  channel,
  combine2,
  combine3,
  combine4,
  fresnel,
  noise2d,
}

class GlintShaderNode {
  const GlintShaderNode({
    required this.id,
    required this.type,
    this.inputs = const {},
    this.properties = const {},
  });

  final String id;
  final GlintShaderNodeType type;
  final Map<String, String> inputs;
  final Map<String, Object?> properties;

  factory GlintShaderNode.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final typeName = json['type'];
    if (id is! String || id.isEmpty || typeName is! String) {
      throw const FormatException('Every shader node needs string id/type.');
    }
    final type = GlintShaderNodeType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () =>
          throw FormatException('Unknown shader node type $typeName.'),
    );
    final rawInputs = json['inputs'];
    final rawProperties = json['properties'];
    if (rawInputs != null && rawInputs is! Map) {
      throw FormatException('$id.inputs must be an object.');
    }
    if (rawProperties != null && rawProperties is! Map) {
      throw FormatException('$id.properties must be an object.');
    }
    Map<String, String> inputs = const {};
    if (rawInputs case final Map values) {
      try {
        inputs = Map<String, String>.from(values);
      } catch (_) {
        throw FormatException('$id.inputs must map names to node ids.');
      }
    }
    return GlintShaderNode(
      id: id,
      type: type,
      inputs: inputs,
      properties: rawProperties == null
          ? const {}
          : Map<String, Object?>.from(rawProperties as Map),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    if (inputs.isNotEmpty) 'inputs': inputs,
    if (properties.isNotEmpty) 'properties': properties,
  };
}

class GlintShaderGraphOutput {
  const GlintShaderGraphOutput({
    this.baseColor,
    this.opacity,
    this.emissive,
    this.metallic,
    this.roughness,
    this.normal,
  });

  final String? baseColor;
  final String? opacity;
  final String? emissive;
  final String? metallic;
  final String? roughness;
  final String? normal;

  factory GlintShaderGraphOutput.fromJson(Map<String, Object?> json) {
    String? output(String name) {
      final value = json[name];
      if (value != null && value is! String) {
        throw FormatException('Shader output $name must be a node id.');
      }
      return value as String?;
    }

    return GlintShaderGraphOutput(
      baseColor: output('baseColor'),
      opacity: output('opacity'),
      emissive: output('emissive'),
      metallic: output('metallic'),
      roughness: output('roughness'),
      normal: output('normal'),
    );
  }

  Map<String, Object?> toJson() => {
    if (baseColor != null) 'baseColor': baseColor,
    if (opacity != null) 'opacity': opacity,
    if (emissive != null) 'emissive': emissive,
    if (metallic != null) 'metallic': metallic,
    if (roughness != null) 'roughness': roughness,
    if (normal != null) 'normal': normal,
  };
}

class GlintShaderGraph {
  const GlintShaderGraph({required this.nodes, required this.output});

  final List<GlintShaderNode> nodes;
  final GlintShaderGraphOutput output;

  factory GlintShaderGraph.fromJson(Map<String, Object?> json) {
    final rawNodes = json['nodes'];
    final rawOutput = json['output'];
    if (rawNodes is! List || rawOutput is! Map) {
      throw const FormatException('Shader graph needs nodes and output.');
    }
    final nodes = <GlintShaderNode>[];
    for (final node in rawNodes) {
      if (node is! Map) {
        throw const FormatException('Every shader node must be an object.');
      }
      nodes.add(GlintShaderNode.fromJson(Map<String, Object?>.from(node)));
    }
    return GlintShaderGraph(
      nodes: nodes,
      output: GlintShaderGraphOutput.fromJson(
        Map<String, Object?>.from(rawOutput),
      ),
    );
  }

  factory GlintShaderGraph.parse(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) {
      throw const FormatException('A shader graph must be a JSON object.');
    }
    return GlintShaderGraph.fromJson(Map<String, Object?>.from(decoded));
  }

  Map<String, Object?> toJson() => {
    'nodes': [for (final node in nodes) node.toJson()],
    'output': output.toJson(),
  };
}

class GlintShaderParameter {
  const GlintShaderParameter({
    required this.name,
    required this.type,
    required this.slot,
    required this.defaultValue,
  });

  final String name;
  final GlintShaderValueType type;
  final int slot;
  final List<double> defaultValue;
}

class GlintCompiledShaderGraph {
  const GlintCompiledShaderGraph({
    required this.fragmentSource,
    required this.parameters,
    required this.textureUniforms,
  });

  final String fragmentSource;
  final Map<String, GlintShaderParameter> parameters;

  /// Logical texture parameter to generated GLSL sampler name.
  final Map<String, String> textureUniforms;
}

class GlintShaderGraphCompiler {
  const GlintShaderGraphCompiler();

  GlintCompiledShaderGraph compile(GlintShaderGraph graph) {
    final compiler = _GraphCompiler(graph);
    return compiler.compile();
  }
}

/// Runtime material referencing a graph fragment inside an offline-compiled
/// Flutter GPU shader bundle.
class GlintShaderGraphMaterial {
  GlintShaderGraphMaterial({
    required this.bundleAsset,
    required this.fragmentEntry,
    required this.program,
    Map<String, Object> parameters = const {},
    Map<String, String> textures = const {},
  }) : parameters = Map.unmodifiable(parameters),
       textures = Map.unmodifiable(textures) {
    if (bundleAsset.trim().isEmpty || fragmentEntry.trim().isEmpty) {
      throw ArgumentError(
        'Shader bundle and fragment names must not be empty.',
      );
    }
    for (final name in parameters.keys) {
      final parameter = program.parameters[name];
      if (parameter == null) {
        throw ArgumentError('Unknown shader parameter "$name".');
      }
      _parameterValue(parameters[name]!, parameter);
    }
    for (final name in textures.keys) {
      if (!program.textureUniforms.containsKey(name)) {
        throw ArgumentError('Unknown shader texture "$name".');
      }
    }
    for (final name in program.textureUniforms.keys) {
      if (!textures.containsKey(name)) {
        throw ArgumentError('Shader texture "$name" has no texture key.');
      }
    }
  }

  final String bundleAsset;
  final String fragmentEntry;
  final GlintCompiledShaderGraph program;
  final Map<String, Object> parameters;

  /// Graph texture parameter to key in `GlintGameView.shaderTextures`.
  final Map<String, String> textures;

  Float32List packUniforms(double time) {
    if (!time.isFinite) {
      throw ArgumentError.value(time, 'time', 'must be finite');
    }
    final output = Float32List(4 + 16 * 4)..[0] = time;
    for (final parameter in program.parameters.values) {
      final value = parameters[parameter.name];
      final packed = value == null
          ? parameter.defaultValue
          : _parameterValue(value, parameter);
      final offset = 4 + parameter.slot * 4;
      for (var i = 0; i < packed.length; i++) {
        output[offset + i] = packed[i];
      }
    }
    return output;
  }
}

List<double> _parameterValue(Object value, GlintShaderParameter parameter) {
  final values = switch (value) {
    num number => [number.toDouble()],
    Vector3 vector => [vector.x, vector.y, vector.z],
    GlintParticleColor color => [color.r, color.g, color.b, color.a],
    List<num> list => [for (final number in list) number.toDouble()],
    _ => throw ArgumentError.value(
      value,
      parameter.name,
      'must be a number, Vector3, color, or numeric list',
    ),
  };
  final required = parameter.type.index + 1;
  if (values.length != required || values.any((item) => !item.isFinite)) {
    throw ArgumentError.value(
      value,
      parameter.name,
      'must contain $required finite component(s)',
    );
  }
  return values;
}

final class _CompiledValue {
  const _CompiledValue(this.type, this.expression);
  final GlintShaderValueType type;
  final String expression;
}

final class _GraphCompiler {
  _GraphCompiler(this.graph);

  final GlintShaderGraph graph;
  final Map<String, GlintShaderNode> _nodes = {};
  final Map<String, _CompiledValue> _compiled = {};
  final Set<String> _visiting = {};
  final List<String> _statements = [];
  final Map<String, GlintShaderParameter> _parameters = {};
  final Map<String, String> _textures = {};

  GlintCompiledShaderGraph compile() {
    for (final node in graph.nodes) {
      if (!_identifier.hasMatch(node.id) || _nodes.containsKey(node.id)) {
        throw FormatException(
          'Invalid or duplicate shader node id ${node.id}.',
        );
      }
      _nodes[node.id] = node;
    }
    final baseColor = _output(graph.output.baseColor);
    final opacity = _output(graph.output.opacity);
    final emissive = _output(graph.output.emissive);
    final metallic = _output(graph.output.metallic);
    final roughness = _output(graph.output.roughness);
    final normal = _output(graph.output.normal);

    _expect(baseColor, const [
      GlintShaderValueType.vector3,
      GlintShaderValueType.vector4,
    ], 'baseColor');
    _expect(opacity, const [GlintShaderValueType.scalar], 'opacity');
    _expect(emissive, const [
      GlintShaderValueType.vector3,
      GlintShaderValueType.vector4,
    ], 'emissive');
    _expect(metallic, const [GlintShaderValueType.scalar], 'metallic');
    _expect(roughness, const [GlintShaderValueType.scalar], 'roughness');
    _expect(normal, const [GlintShaderValueType.vector3], 'normal');

    final samplers = [
      for (final entry in _textures.entries)
        'uniform sampler2D ${entry.value};',
    ].join('\n');
    final baseExpression = baseColor == null
        ? 'texture(tex, v_texture_coords)'
        : baseColor.type == GlintShaderValueType.vector3
        ? 'vec4(${baseColor.expression}, 1.0)'
        : baseColor.expression;
    final emissiveExpression = emissive == null
        ? 'vec3(0.0)'
        : emissive.type == GlintShaderValueType.vector4
        ? '${emissive.expression}.rgb'
        : emissive.expression;
    final source =
        '''
#include "material_graph_types.glsl"
$samplers

GlintGraphSurface glint_graph_surface() {
${_statements.map((line) => '  $line').join('\n')}
  GlintGraphSurface surface;
  surface.base_color = $baseExpression;
  surface.opacity = ${opacity?.expression ?? '1.0'};
  surface.emissive = $emissiveExpression;
  surface.metallic = ${metallic?.expression ?? 'v_material.x'};
  surface.roughness = ${roughness?.expression ?? 'v_material.y'};
  surface.normal = ${normal?.expression ?? 'normalize(v_normal)'};
  return surface;
}

#include "material_graph_pbr.glsl"
''';
    return GlintCompiledShaderGraph(
      fragmentSource: source,
      parameters: Map.unmodifiable(_parameters),
      textureUniforms: Map.unmodifiable(_textures),
    );
  }

  _CompiledValue? _output(String? id) => id == null ? null : _compile(id);

  _CompiledValue _compile(String id) {
    final cached = _compiled[id];
    if (cached != null) return cached;
    final node = _nodes[id];
    if (node == null) throw FormatException('Unknown shader node "$id".');
    if (!_visiting.add(id)) {
      throw FormatException('Shader graph contains a cycle at "$id".');
    }
    final direct = _compileNode(node);
    final value = switch (node.type) {
      GlintShaderNodeType.uv ||
      GlintShaderNodeType.time ||
      GlintShaderNodeType.worldPosition ||
      GlintShaderNodeType.worldNormal ||
      GlintShaderNodeType.viewDirection ||
      GlintShaderNodeType.baseTexture ||
      GlintShaderNodeType.parameter => direct,
      _ => _temporary(node.id, direct),
    };
    _visiting.remove(id);
    _compiled[id] = value;
    return value;
  }

  _CompiledValue _compileNode(GlintShaderNode node) => switch (node.type) {
    GlintShaderNodeType.uv => const _CompiledValue(
      GlintShaderValueType.vector2,
      'v_texture_coords',
    ),
    GlintShaderNodeType.time => const _CompiledValue(
      GlintShaderValueType.scalar,
      'graph_info.runtime.x',
    ),
    GlintShaderNodeType.worldPosition => const _CompiledValue(
      GlintShaderValueType.vector3,
      'v_world_position',
    ),
    GlintShaderNodeType.worldNormal => const _CompiledValue(
      GlintShaderValueType.vector3,
      'normalize(v_normal)',
    ),
    GlintShaderNodeType.viewDirection => const _CompiledValue(
      GlintShaderValueType.vector3,
      'normalize(frame_info.camera_position.xyz - v_world_position)',
    ),
    GlintShaderNodeType.baseTexture => const _CompiledValue(
      GlintShaderValueType.vector4,
      'texture(tex, v_texture_coords)',
    ),
    GlintShaderNodeType.constant => _constant(node),
    GlintShaderNodeType.parameter => _parameter(node),
    GlintShaderNodeType.textureSample => _texture(node),
    GlintShaderNodeType.add => _binary(node, '+'),
    GlintShaderNodeType.subtract => _binary(node, '-'),
    GlintShaderNodeType.multiply => _binary(node, '*'),
    GlintShaderNodeType.divide => _binary(node, '/'),
    GlintShaderNodeType.mix => _mix(node),
    GlintShaderNodeType.power => _binary(node, 'pow', function: true),
    GlintShaderNodeType.sine => _unary(node, 'sin'),
    GlintShaderNodeType.cosine => _unary(node, 'cos'),
    GlintShaderNodeType.absolute => _unary(node, 'abs'),
    GlintShaderNodeType.oneMinus => _oneMinus(node),
    GlintShaderNodeType.saturate => _unary(node, 'glint_saturate'),
    GlintShaderNodeType.normalize => _normalize(node),
    GlintShaderNodeType.dot => _dot(node),
    GlintShaderNodeType.channel => _channel(node),
    GlintShaderNodeType.combine2 => _combine(node, 2),
    GlintShaderNodeType.combine3 => _combine(node, 3),
    GlintShaderNodeType.combine4 => _combine(node, 4),
    GlintShaderNodeType.fresnel => _fresnel(node),
    GlintShaderNodeType.noise2d => _noise(node),
  };

  _CompiledValue _constant(GlintShaderNode node) {
    final raw = node.properties['value'];
    final values = _numbers(raw, '${node.id}.value');
    final type = _typeForLength(values.length, node.id);
    return _CompiledValue(type, _literal(values));
  }

  _CompiledValue _parameter(GlintShaderNode node) {
    final name = node.properties['name'];
    if (name is! String || !_identifier.hasMatch(name)) {
      throw FormatException('${node.id}.name is not a GLSL identifier.');
    }
    final defaults = _numbers(node.properties['default'], '${node.id}.default');
    final type = _typeForLength(defaults.length, node.id);
    final existing = _parameters[name];
    if (existing != null &&
        (existing.type != type ||
            !_listEquals(existing.defaultValue, defaults))) {
      throw FormatException(
        'Shader parameter "$name" is declared differently.',
      );
    }
    if (existing == null) {
      if (_parameters.length >= 16) {
        throw const FormatException('A graph supports at most 16 parameters.');
      }
      _parameters[name] = GlintShaderParameter(
        name: name,
        type: type,
        slot: _parameters.length,
        defaultValue: List.unmodifiable(defaults),
      );
    }
    final parameter = _parameters[name]!;
    final suffix = switch (type) {
      GlintShaderValueType.scalar => '.x',
      GlintShaderValueType.vector2 => '.xy',
      GlintShaderValueType.vector3 => '.xyz',
      GlintShaderValueType.vector4 => '',
    };
    return _CompiledValue(
      type,
      'graph_info.parameters[${parameter.slot}]$suffix',
    );
  }

  _CompiledValue _texture(GlintShaderNode node) {
    final name = node.properties['name'];
    if (name is! String || !_identifier.hasMatch(name)) {
      throw FormatException('${node.id}.name is not a GLSL identifier.');
    }
    final uv = _input(node, 'uv');
    _requireType(uv, GlintShaderValueType.vector2, '${node.id}.uv');
    final uniform = _textures.putIfAbsent(name, () {
      if (_textures.length >= 8) {
        throw const FormatException('A graph supports at most 8 textures.');
      }
      return 'graph_texture_${_textures.length}';
    });
    return _CompiledValue(
      GlintShaderValueType.vector4,
      'texture($uniform, ${uv.expression})',
    );
  }

  _CompiledValue _binary(
    GlintShaderNode node,
    String operator, {
    bool function = false,
  }) {
    final a = _input(node, 'a');
    final b = _input(node, 'b');
    final type = _compatibleType(a.type, b.type, node.id);
    final expression = function
        ? '$operator(${a.expression}, ${b.expression})'
        : '(${a.expression} $operator ${b.expression})';
    return _CompiledValue(type, expression);
  }

  _CompiledValue _mix(GlintShaderNode node) {
    final a = _input(node, 'a');
    final b = _input(node, 'b');
    final t = _input(node, 't');
    final type = _compatibleType(a.type, b.type, node.id);
    if (t.type != GlintShaderValueType.scalar && t.type != type) {
      throw FormatException('${node.id}.t must be scalar or match a/b.');
    }
    return _CompiledValue(
      type,
      'mix(${a.expression}, ${b.expression}, ${t.expression})',
    );
  }

  _CompiledValue _unary(GlintShaderNode node, String function) {
    final value = _input(node, 'value');
    return _CompiledValue(value.type, '$function(${value.expression})');
  }

  _CompiledValue _oneMinus(GlintShaderNode node) {
    final value = _input(node, 'value');
    return _CompiledValue(value.type, '(1.0 - ${value.expression})');
  }

  _CompiledValue _normalize(GlintShaderNode node) {
    final value = _input(node, 'value');
    if (value.type == GlintShaderValueType.scalar) {
      throw FormatException('${node.id}.value must be a vector.');
    }
    return _CompiledValue(value.type, 'normalize(${value.expression})');
  }

  _CompiledValue _dot(GlintShaderNode node) {
    final a = _input(node, 'a');
    final b = _input(node, 'b');
    if (a.type == GlintShaderValueType.scalar || a.type != b.type) {
      throw FormatException('${node.id} dot inputs must be matching vectors.');
    }
    return _CompiledValue(
      GlintShaderValueType.scalar,
      'dot(${a.expression}, ${b.expression})',
    );
  }

  _CompiledValue _channel(GlintShaderNode node) {
    final value = _input(node, 'value');
    final channel = node.properties['channel'];
    const channels = ['x', 'y', 'z', 'w'];
    if (channel is! String ||
        !channels.take(value.type.index + 1).contains(channel)) {
      throw FormatException('${node.id}.channel is outside its input vector.');
    }
    return _CompiledValue(
      GlintShaderValueType.scalar,
      '${value.expression}.$channel',
    );
  }

  _CompiledValue _combine(GlintShaderNode node, int count) {
    const names = ['x', 'y', 'z', 'w'];
    final inputs = [for (var i = 0; i < count; i++) _input(node, names[i])];
    for (var i = 0; i < inputs.length; i++) {
      _requireType(
        inputs[i],
        GlintShaderValueType.scalar,
        '${node.id}.${names[i]}',
      );
    }
    return _CompiledValue(
      GlintShaderValueType.values[count - 1],
      'vec$count(${inputs.map((input) => input.expression).join(', ')})',
    );
  }

  _CompiledValue _fresnel(GlintShaderNode node) {
    final power = node.inputs.containsKey('power')
        ? _input(node, 'power')
        : const _CompiledValue(GlintShaderValueType.scalar, '5.0');
    _requireType(power, GlintShaderValueType.scalar, '${node.id}.power');
    return _CompiledValue(
      GlintShaderValueType.scalar,
      'pow(1.0 - clamp(dot(normalize(v_normal), '
      'normalize(frame_info.camera_position.xyz - v_world_position)), '
      '0.0, 1.0), ${power.expression})',
    );
  }

  _CompiledValue _noise(GlintShaderNode node) {
    final uv = _input(node, 'uv');
    _requireType(uv, GlintShaderValueType.vector2, '${node.id}.uv');
    return _CompiledValue(
      GlintShaderValueType.scalar,
      'glint_noise2d(${uv.expression})',
    );
  }

  _CompiledValue _input(GlintShaderNode node, String name) {
    final id = node.inputs[name];
    if (id == null) {
      throw FormatException('${node.id} is missing input "$name".');
    }
    return _compile(id);
  }

  _CompiledValue _temporary(String id, _CompiledValue value) {
    final name = 'node_$id';
    _statements.add('${_glslType(value.type)} $name = ${value.expression};');
    return _CompiledValue(value.type, name);
  }
}

final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

List<double> _numbers(Object? value, String label) {
  late final List<double> result;
  if (value is num) {
    result = [value.toDouble()];
  } else if (value is List && value.every((item) => item is num)) {
    result = [for (final item in value) (item as num).toDouble()];
  } else {
    throw FormatException('$label must be a number or numeric list.');
  }
  if (result.isEmpty ||
      result.length > 4 ||
      result.any((item) => !item.isFinite)) {
    throw FormatException('$label must contain 1 to 4 finite values.');
  }
  return result;
}

GlintShaderValueType _typeForLength(int length, String label) {
  if (length < 1 || length > 4) {
    throw FormatException('$label must have 1 to 4 components.');
  }
  return GlintShaderValueType.values[length - 1];
}

String _literal(List<double> values) {
  String scalar(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}.0' : value.toString();
  if (values.length == 1) return scalar(values.first);
  return 'vec${values.length}(${values.map(scalar).join(', ')})';
}

String _glslType(GlintShaderValueType type) => switch (type) {
  GlintShaderValueType.scalar => 'float',
  GlintShaderValueType.vector2 => 'vec2',
  GlintShaderValueType.vector3 => 'vec3',
  GlintShaderValueType.vector4 => 'vec4',
};

GlintShaderValueType _compatibleType(
  GlintShaderValueType a,
  GlintShaderValueType b,
  String label,
) {
  if (a == b) return a;
  if (a == GlintShaderValueType.scalar) return b;
  if (b == GlintShaderValueType.scalar) return a;
  throw FormatException('$label inputs must match or one must be scalar.');
}

void _requireType(
  _CompiledValue value,
  GlintShaderValueType type,
  String label,
) {
  if (value.type != type) throw FormatException('$label must be ${type.name}.');
}

void _expect(
  _CompiledValue? value,
  List<GlintShaderValueType> types,
  String label,
) {
  if (value != null && !types.contains(value.type)) {
    throw FormatException('$label has incompatible type ${value.type.name}.');
  }
}

bool _listEquals(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
