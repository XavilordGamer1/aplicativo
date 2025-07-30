// Analizador de Rutas de Proyecto
// Una aplicación de escritorio y móvil desarrollada con Flutter para calcular y visualizar la ruta crítica de proyectos.
//
// ## Autor
//
// * **Desarrollador Principal:** Xavier Baque y Jordan Pincha
// * **Contacto:** xavier.18.2018@hotmail.com
//
// ## Propiedad Intelectual
//
// © 2025 Xavier Fernando Baque Velez. Todos los derechos reservados.
//
// Este proyecto está protegido bajo la Licencia MIT. Por favor, consulte el archivo `LICENSE` para más detalles.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:graphs/graphs.dart' as graphs;
import 'package:graphview/GraphView.dart' as gv;
import 'dart:math';

// --- ESTRUCTURAS Y ENUMS ---

enum GraphViewMode { Graph, Table }

enum GraphNodeStyle { DetailedBox, SimpleCircle } // <-- NUEVO

class Connection {
  final TextEditingController originController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  final TextEditingController durationController = TextEditingController();
}

class NodeData {
  int es = 0; // Earliest Start (Inicio más temprano)
  int ef = 0; // Earliest Finish (Fin más temprano)
  int ls = 0; // Latest Start (Inicio más tardío)
  int lf = 0; // Latest Finish (Fin más tardío)
  int slack = 0; // Holgura
}

// --- CLASE DE ESTADO PRINCIPAL ---

class GraphState with ChangeNotifier {
  List<Connection> connections = [Connection()];
  final TextEditingController startNodeController = TextEditingController();
  final TextEditingController endNodeController = TextEditingController();

  String shortestPathResult = 'Aún no calculado.';
  String longestPathResult = 'Aún no calculado.';

  gv.Graph graphView = gv.Graph();
  gv.BuchheimWalkerConfiguration builder = gv.BuchheimWalkerConfiguration();
  Map<String, NodeData> cpmData = {};

  GraphViewMode _viewMode = GraphViewMode.Graph;
  GraphViewMode get viewMode => _viewMode;

  // ¡NUEVO! Estado para controlar el estilo del nodo del grafo
  GraphNodeStyle _nodeStyle = GraphNodeStyle.DetailedBox;
  GraphNodeStyle get nodeStyle => _nodeStyle;

  void setViewMode(GraphViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }

  // ¡NUEVO! Setter para el estilo del nodo
  void setNodeStyle(GraphNodeStyle style) {
    _nodeStyle = style;
    // Reconstruir el grafo con el nuevo estilo sin recalcular todo
    if (cpmData.isNotEmpty) {
      final graph = <String, Map<String, int>>{};
      final allNodeNames = <String>{};
      for (var conn in connections) {
        final origin = conn.originController.text.trim().toUpperCase();
        final dest = conn.destinationController.text.trim().toUpperCase();
        final duration = int.tryParse(conn.durationController.text.trim()) ?? 0;
        if (origin.isNotEmpty && dest.isNotEmpty) {
          graph.putIfAbsent(origin, () => {})[dest] = duration;
          allNodeNames.add(origin);
          allNodeNames.add(dest);
        }
      }
      _buildGraphView(graph, allNodeNames);
    }
    notifyListeners();
  }

  void addConnection() {
    connections.add(Connection());
    notifyListeners();
  }

  void removeConnection(int index) {
    if (connections.length > 1) {
      connections[index].originController.dispose();
      connections[index].destinationController.dispose();
      connections[index].durationController.dispose();
      connections.removeAt(index);
      notifyListeners();
    }
  }

  void resetState() {
    for (var conn in connections) {
      conn.originController.clear();
      conn.destinationController.clear();
      conn.durationController.clear();
    }
    if (connections.length > 1) {
      connections.removeRange(1, connections.length);
    }
    startNodeController.clear();
    endNodeController.clear();
    shortestPathResult = 'Aún no calculado.';
    longestPathResult = 'Aún no calculado.';
    graphView = gv.Graph();
    cpmData.clear();
    notifyListeners();
  }

  void calculatePaths(BuildContext context) {
    final graph = <String, Map<String, int>>{};
    final allNodeNames = <String>{};

    for (var conn in connections) {
      final origin = conn.originController.text.trim().toUpperCase();
      final dest = conn.destinationController.text.trim().toUpperCase();
      final durationStr = conn.durationController.text.trim();

      if (origin.isEmpty || dest.isEmpty || durationStr.isEmpty) {
        _showAlertDialog(context, 'Error',
            'Todos los campos de conexión deben estar llenos.');
        return;
      }
      final duration = int.tryParse(durationStr);
      if (duration == null || duration < 0) {
        _showAlertDialog(context, 'Error',
            'La duración debe ser un número entero no negativo.');
        return;
      }
      graph.putIfAbsent(origin, () => {})[dest] = duration;
      allNodeNames.add(origin);
      allNodeNames.add(dest);
    }

    final startNode = startNodeController.text.trim().toUpperCase();
    final endNode = endNodeController.text.trim().toUpperCase();

    if (startNode.isEmpty || endNode.isEmpty) {
      _showAlertDialog(
          context, 'Error', 'Debe especificar un nodo inicial y final.');
      return;
    }
    if (!allNodeNames.contains(startNode) || !allNodeNames.contains(endNode)) {
      _showAlertDialog(context, 'Error',
          'El nodo de inicio o fin no existe en las conexiones definidas.');
      return;
    }

    try {
      final shortest = _dijkstra(graph, startNode, endNode, allNodeNames);
      if (shortest.isEmpty) {
        shortestPathResult = 'No se encontró una ruta.';
      } else {
        final shortestDuration = _calculatePathDuration(graph, shortest);
        shortestPathResult =
            '${shortest.join(' → ')} (Duración: $shortestDuration semanas)';
      }
    } catch (e) {
      shortestPathResult = 'Error al calcular la ruta corta.';
    }

    try {
      final allPaths = _findAllPaths(graph, startNode, endNode);
      if (allPaths.isEmpty) {
        longestPathResult = 'No se encontró una ruta.';
        graphView = gv.Graph();
        cpmData.clear();
      } else {
        List<String> longestPath = [];
        int maxDuration = -1;
        for (var path in allPaths) {
          int currentDuration = _calculatePathDuration(graph, path);
          if (currentDuration > maxDuration) {
            maxDuration = currentDuration;
            longestPath = path;
          }
        }
        longestPathResult =
            '${longestPath.join(' → ')} (Duración: $maxDuration semanas)';
        cpmData =
            _calculateCPM(graph, allNodeNames.toList(), startNode, endNode);
        _buildGraphView(graph, allNodeNames);
      }
    } catch (e) {
      longestPathResult = 'Error al calcular la ruta larga.';
      graphView = gv.Graph();
      cpmData.clear();
    }
    notifyListeners();
  }

  // --- MÉTODOS DE CÁLCULO (sin cambios) ---
  List<String> _dijkstra(Map<String, Map<String, int>> graph, String start,
      String end, Set<String> allNodes) {
    var distances = <String, int>{};
    var previous = <String, String?>{};
    var nodes = allNodes.toSet();
    for (var vertex in nodes) {
      distances[vertex] = 999999;
      previous[vertex] = null;
    }
    distances[start] = 0;
    while (nodes.isNotEmpty) {
      String? smallest;
      for (var node in nodes) {
        if (smallest == null || distances[node]! < distances[smallest]!)
          smallest = node;
      }
      if (smallest == null || distances[smallest] == 999999) break;
      nodes.remove(smallest);
      if (smallest == end) {
        final path = <String>[];
        String? current = smallest;
        while (current != null) {
          path.insert(0, current);
          current = previous[current];
        }
        return path;
      }
      if (graph[smallest] == null) continue;
      for (var neighbor in graph[smallest]!.keys) {
        var alt = distances[smallest]! + graph[smallest]![neighbor]!;
        if (alt < distances[neighbor]!) {
          distances[neighbor] = alt;
          previous[neighbor] = smallest;
        }
      }
    }
    return [];
  }

  Map<String, NodeData> _calculateCPM(Map<String, Map<String, int>> graph,
      List<String> allNodes, String startNode, String endNode) {
    Map<String, NodeData> data = {for (var node in allNodes) node: NodeData()};
    var sortedNodes =
        graphs.topologicalSort(allNodes, (n) => graph[n]?.keys ?? []).toList();
    for (var node in sortedNodes) {
      var predecessors =
          allNodes.where((p) => graph[p]?.containsKey(node) ?? false);
      int maxEf = 0;
      for (var pred in predecessors) {
        int currentEf = data[pred]!.ef + (graph[pred]![node] ?? 0);
        if (currentEf > maxEf) maxEf = currentEf;
      }
      data[node]!.ef = maxEf;
      data[node]!.es = maxEf;
    }
    int projectDuration = data[endNode]!.ef;
    for (var nodeData in data.values) {
      nodeData.lf = projectDuration;
    }
    for (var node in sortedNodes.reversed) {
      var successors = (graph[node]?.keys ?? []).toList();
      if (node == endNode) {
        data[node]!.lf = data[node]!.ef;
      } else {
        int minLs = projectDuration;
        if (successors.isNotEmpty) {
          for (var succ in successors) {
            int currentLs = data[succ]!.ls - (graph[node]![succ] ?? 0);
            if (currentLs < minLs) minLs = currentLs;
          }
          data[node]!.lf = minLs;
        }
      }
    }
    for (var node in allNodes) {
      data[node]!.ls = data[node]!.lf;
      data[node]!.slack = data[node]!.lf - data[node]!.ef;
    }
    return data;
  }

  int _calculatePathDuration(
      Map<String, Map<String, int>> graph, List<String> path) {
    int total = 0;
    for (int i = 0; i < path.length - 1; i++) {
      total += graph[path[i]]![path[i + 1]] ?? 0;
    }
    return total;
  }

  List<List<String>> _findAllPaths(
      Map<String, Map<String, int>> graph, String start, String end) {
    List<List<String>> allPaths = [];
    List<String> currentPath = [start];
    void dfs(String currentNode) {
      if (currentNode == end) {
        allPaths.add(List.from(currentPath));
        return;
      }
      final neighbors = graph[currentNode]?.keys.toList() ?? [];
      for (var neighbor in neighbors) {
        if (!currentPath.contains(neighbor)) {
          currentPath.add(neighbor);
          dfs(neighbor);
          currentPath.removeLast();
        }
      }
    }

    dfs(start);
    return allPaths;
  }

  // --- MÉTODOS DE CONSTRUCCIÓN DE WIDGETS ---
  void _buildGraphView(
      Map<String, Map<String, int>> logicGraph, Set<String> nodeNames) {
    final gvGraph = gv.Graph();
    final Map<String, gv.Node> nodesMap = {};
    for (var name in nodeNames) {
      final nodeCpmData = cpmData[name] ?? NodeData();

      // ¡NUEVO! Decide qué widget de nodo construir
      Widget nodeWidget;
      if (_nodeStyle == GraphNodeStyle.DetailedBox) {
        nodeWidget = _buildDetailedBoxNodeWidget(name, nodeCpmData);
      } else {
        nodeWidget = _buildSimpleCircleNodeWidget(name, nodeCpmData.slack == 0);
      }

      nodesMap[name] = gv.Node(nodeWidget);
      gvGraph.addNode(nodesMap[name]!);
    }
    logicGraph.forEach((node, neighbors) {
      neighbors.keys.forEach((neighbor) {
        if (nodesMap.containsKey(node) && nodesMap.containsKey(neighbor)) {
          final isCritical =
              (cpmData[node]?.slack == 0) && (cpmData[neighbor]?.slack == 0);
          gvGraph.addEdge(nodesMap[node]!, nodesMap[neighbor]!,
              paint: Paint()
                ..color = isCritical ? Colors.redAccent : Colors.grey
                ..strokeWidth = isCritical ? 2.5 : 1.5);
        }
      });
    });
    graphView = gvGraph;
    builder
      ..siblingSeparation = (50)
      ..levelSeparation = (50)
      ..subtreeSeparation = (50)
      ..orientation = (gv.BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT);
  }

  // Renombrada para mayor claridad
  Widget _buildDetailedBoxNodeWidget(String name, NodeData data) {
    bool isCritical = data.slack == 0;
    return Container(
        width: 120,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isCritical
              ? Colors.red.withOpacity(0.1)
              : Colors.black.withOpacity(0.2),
          border: Border.all(
              color: isCritical ? Colors.redAccent : Colors.indigoAccent,
              width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: isCritical ? Colors.red.shade900 : Colors.indigo.shade800,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          const Divider(height: 10, thickness: 1),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildCpmValue("IC", data.es),
            _buildCpmValue("TC", data.ef)
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildCpmValue("IL", data.ls),
            _buildCpmValue("TL", data.lf)
          ]),
        ]));
  }

  // ¡NUEVO! Widget para el nodo de círculo simple
  Widget _buildSimpleCircleNodeWidget(String name, bool isCritical) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCritical
            ? Colors.red.withOpacity(0.2)
            : Colors.black.withOpacity(0.3),
        border: Border.all(
          color: isCritical ? Colors.redAccent : Colors.indigoAccent,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          name,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCpmValue(String label, int value) => Column(children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        Text(value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ]);

  void _showAlertDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              child: const Text("OK"),
              onPressed: () => Navigator.of(context).pop())
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (var connection in connections) {
      connection.originController.dispose();
      connection.destinationController.dispose();
      connection.durationController.dispose();
    }
    startNodeController.dispose();
    endNodeController.dispose();
    super.dispose();
  }
}

void main() => runApp(ChangeNotifierProvider(
    create: (context) => GraphState(), child: const CriticalPathApp()));

class CriticalPathApp extends StatelessWidget {
  const CriticalPathApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Analizador de Rutas de Proyecto',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
        cardTheme: CardThemeData(
            elevation: 4,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
      ),
      home: const GraphHomePage(),
    );
  }
}

class GraphHomePage extends StatelessWidget {
  const GraphHomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analizador de Rutas de Proyecto')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InputPanel(),
              const SizedBox(height: 24),
              _GraphVisualizer(),
              const SizedBox(height: 24),
              _ResultsPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputPanel extends StatelessWidget {
  Future<void> _showResetConfirmationDialog(
      BuildContext context, GraphState state) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Reseteo'),
          content: const Text(
              '¿Estás seguro de que quieres borrar todos los datos?'),
          actions: <Widget>[
            TextButton(
                child: const Text('Cancelar'),
                onPressed: () => Navigator.of(context).pop()),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Resetear'),
              onPressed: () {
                state.resetState();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GraphState>(builder: (context, state, child) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Panel de Entrada',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              const Row(children: [
                Expanded(
                    child: Text('Origen',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    child: Text('Destino',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    child: Text('Duración (sem)',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 48),
              ]),
              const Divider(),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.connections.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(children: [
                    Expanded(
                        child: _buildTextField(
                            state.connections[index].originController)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildTextField(
                            state.connections[index].destinationController)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildTextField(
                            state.connections[index].durationController,
                            isNumber: true)),
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => state.removeConnection(index)),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir Fila'),
                    onPressed: state.addConnection),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                    child: _buildLabeledTextField(
                        'Nodo Inicial', state.startNodeController)),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildLabeledTextField(
                        'Nodo Final', state.endNodeController)),
              ]),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Resetear'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        textStyle: Theme.of(context).textTheme.titleMedium),
                    onPressed: () =>
                        _showResetConfirmationDialog(context, state),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.calculate),
                    label: const Text('Calcular Rutas'),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        textStyle: Theme.of(context).textTheme.titleMedium),
                    onPressed: () => state.calculatePaths(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildTextField(TextEditingController controller,
          {bool isNumber = false}) =>
      TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration:
            const InputDecoration(border: OutlineInputBorder(), isDense: true),
      );

  Widget _buildLabeledTextField(
          String label, TextEditingController controller) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildTextField(controller),
        ],
      );
}

class _GraphVisualizer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Consumer<GraphState>(
        builder: (context, state, child) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: SegmentedButton<GraphViewMode>(
                  segments: const [
                    ButtonSegment(
                        value: GraphViewMode.Graph,
                        label: Text('Grafo'),
                        icon: Icon(Icons.share)),
                    ButtonSegment(
                        value: GraphViewMode.Table,
                        label: Text('Tabla'),
                        icon: Icon(Icons.table_chart)),
                  ],
                  selected: {state.viewMode},
                  onSelectionChanged: (Set<GraphViewMode> newSelection) {
                    state.setViewMode(newSelection.first);
                  },
                ),
              ),
              // ¡NUEVO! Selector de estilo de nodo, solo visible en modo Grafo
              if (state.viewMode == GraphViewMode.Graph)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: SegmentedButton<GraphNodeStyle>(
                    segments: const [
                      ButtonSegment(
                          value: GraphNodeStyle.DetailedBox,
                          label: Text('Detallado')),
                      ButtonSegment(
                          value: GraphNodeStyle.SimpleCircle,
                          label: Text('Simple')),
                    ],
                    selected: {state.nodeStyle},
                    onSelectionChanged: (Set<GraphNodeStyle> newSelection) {
                      state.setNodeStyle(newSelection.first);
                    },
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(16.0),
                height: 400,
                child: _buildCurrentView(context, state),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCurrentView(BuildContext context, GraphState state) {
    if (state.cpmData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.device_hub, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Visualización',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text("Presiona 'Calcular Rutas' para ver los resultados.",
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    switch (state.viewMode) {
      case GraphViewMode.Graph:
        return InteractiveViewer(
          constrained: false,
          boundaryMargin: const EdgeInsets.all(100),
          minScale: 0.01,
          maxScale: 5.6,
          child: gv.GraphView(
            graph: state.graphView,
            algorithm: gv.BuchheimWalkerAlgorithm(
                state.builder, gv.TreeEdgeRenderer(state.builder)),
            paint: Paint()
              ..color = Colors.grey
              ..strokeWidth = 1
              ..style = PaintingStyle.stroke,
            builder: (gv.Node node) => node.data as Widget,
          ),
        );
      case GraphViewMode.Table:
        return _ResultsTable();
    }
  }
}

class _ResultsTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<GraphState>();
    final dataRows = state.cpmData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(
                label: Text('Actividad',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label:
                    Text('IC', style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true),
            DataColumn(
                label:
                    Text('TC', style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true),
            DataColumn(
                label:
                    Text('IL', style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true),
            DataColumn(
                label:
                    Text('TL', style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true),
            DataColumn(
                label: Text('Holgura',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true),
          ],
          rows: dataRows.map((entry) {
            final nodeName = entry.key;
            final data = entry.value;
            final isCritical = data.slack == 0;
            final criticalStyle = TextStyle(
                color: Colors.red.shade300, fontWeight: FontWeight.bold);

            return DataRow(
              color: MaterialStateProperty.resolveWith<Color?>((states) {
                if (isCritical) return Colors.red.withOpacity(0.15);
                return null;
              }),
              cells: [
                DataCell(
                    Text(nodeName, style: isCritical ? criticalStyle : null)),
                DataCell(Text(data.es.toString(),
                    style: isCritical ? criticalStyle : null)),
                DataCell(Text(data.ef.toString(),
                    style: isCritical ? criticalStyle : null)),
                DataCell(Text(data.ls.toString(),
                    style: isCritical ? criticalStyle : null)),
                DataCell(Text(data.lf.toString(),
                    style: isCritical ? criticalStyle : null)),
                DataCell(Text(data.slack.toString(),
                    style: isCritical ? criticalStyle : null)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ResultsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<GraphState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Panel de Resultados',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildResultRow('Ruta más Corta:', state.shortestPathResult),
            const SizedBox(height: 8),
            _buildResultRow(
                'Ruta más Larga (Crítica):', state.longestPathResult),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String result) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(result)),
        ],
      );
}
