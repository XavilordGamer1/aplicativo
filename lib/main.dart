import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:graphs/graphs.dart' as graphs;
import 'package:graphview/GraphView.dart' as gv;
import 'dart:math';

// --- ESTRUCTURAS DE DATOS ---

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
  Map<String, NodeData> cpmData = {};

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

  // --- NUEVA FUNCIÓN DE RESETEO ---
  void resetState() {
    print("\n===== ESTADO RESETEADO =====");
    // Limpiar todas las conexiones y dejar una en blanco
    for (var conn in connections) {
      conn.originController.clear();
      conn.destinationController.clear();
      conn.durationController.clear();
    }
    connections.removeRange(1, connections.length);

    // Limpiar campos y resultados
    startNodeController.clear();
    endNodeController.clear();
    shortestPathResult = 'Aún no calculado.';
    longestPathResult = 'Aún no calculado.';
    graphView = gv.Graph();
    cpmData.clear();

    notifyListeners();
  }

  // --- LÓGICA DE CÁLCULO PRINCIPAL ---
  void calculatePaths(BuildContext context) {
    print("\n\n===== INICIANDO CÁLCULO DE RUTAS =====");

    final graph = <String, Map<String, int>>{};
    final allNodeNames = <String>{};

    for (var conn in connections) {
      final origin = conn.originController.text.trim();
      final dest = conn.destinationController.text.trim();
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

    print("✅ Grafo construido desde la entrada:");
    graph.forEach((key, value) {
      print("   - Desde '$key' -> $value");
    });

    final startNode = startNodeController.text.trim();
    final endNode = endNodeController.text.trim();
    print("📍 Nodo de Inicio: '$startNode', Nodo Final: '$endNode'");

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

    print("\n--- Calculando Ruta Más Corta (Dijkstra) ---");
    try {
      final shortest = _dijkstra(graph, startNode, endNode, allNodeNames);

      if (shortest.isEmpty) {
        shortestPathResult = 'No se encontró una ruta.';
      } else {
        final shortestDuration = _calculatePathDuration(graph, shortest);
        shortestPathResult =
            '${shortest.join(' → ')} (Duración: $shortestDuration semanas)';
      }
      print("Resultado Ruta Corta: $shortestPathResult");
    } catch (e) {
      shortestPathResult = 'Error al calcular la ruta corta.';
      print("Error en Dijkstra: $e");
    }

    print("\n--- Calculando Ruta Crítica y CPM ---");
    try {
      final allPaths = _findAllPaths(graph, startNode, endNode);
      print(
          "Se encontraron ${allPaths.length} rutas posibles entre '$startNode' y '$endNode'.");

      if (allPaths.isEmpty) {
        longestPathResult = 'No se encontró una ruta.';
        graphView = gv.Graph();
      } else {
        List<String> longestPath = [];
        int maxDuration = 0;
        for (var path in allPaths) {
          int currentDuration = _calculatePathDuration(graph, path);
          if (currentDuration > maxDuration) {
            maxDuration = currentDuration;
            longestPath = path;
          }
        }
        longestPathResult =
            '${longestPath.join(' → ')} (Duración: $maxDuration semanas)';
        print("Resultado Ruta Larga (Crítica): $longestPathResult");

        print("\n--- Realizando Análisis CPM ---");
        cpmData =
            _calculateCPM(graph, allNodeNames.toList(), startNode, endNode);
        cpmData.forEach((node, data) {
          print(
              "Nodo: $node | IC:${data.es} TC:${data.ef} | IL:${data.ls} TL:${data.lf} | Holgura:${data.slack}");
        });

        _buildGraphView(graph, allNodeNames, longestPath);
      }
    } catch (e) {
      longestPathResult = 'Error al calcular la ruta larga.';
      graphView = gv.Graph();
      print("Error en CPM o Ruta Larga: $e");
    }

    print("===== CÁLCULO FINALIZADO =====");
    notifyListeners();
  }

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
        if (smallest == null || distances[node]! < distances[smallest]!) {
          smallest = node;
        }
      }

      if (smallest == null || distances[smallest] == 999999) break;

      nodes.remove(smallest);

      if (smallest == end) {
        final path = <String>[];
        String? currentNullable = smallest;
        while (currentNullable != null) {
          final String current = currentNullable;
          path.insert(0, current);
          currentNullable = previous[current];
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

  Map<String, NodeData> _calculateCPM(
    Map<String, Map<String, int>> graph,
    List<String> allNodes,
    String startNode,
    String endNode,
  ) {
    Map<String, NodeData> data = {for (var node in allNodes) node: NodeData()};
    var sortedNodes =
        graphs.topologicalSort(allNodes, (n) => graph[n]?.keys ?? []).toList();

    for (var node in sortedNodes) {
      var predecessors =
          allNodes.where((p) => graph[p]?.containsKey(node) ?? false);
      int maxEf = 0;
      for (var pred in predecessors) {
        int currentEf = data[pred]!.ef + (graph[pred]![node] ?? 0);
        if (currentEf > maxEf) {
          maxEf = currentEf;
        }
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
        int minLf = projectDuration;
        if (successors.isNotEmpty) {
          for (var succ in successors) {
            int currentLf = data[succ]!.lf - (graph[node]![succ] ?? 0);
            if (currentLf < minLf) {
              minLf = currentLf;
            }
          }
        }
        data[node]!.lf = minLf;
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
    Map<String, Map<String, int>> graph,
    String start,
    String end,
  ) {
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

  void _buildGraphView(
    Map<String, Map<String, int>> logicGraph,
    Set<String> nodeNames,
    List<String> criticalPath,
  ) {
    final gvGraph = gv.Graph();
    final Map<String, gv.Node> nodesMap = {};

    for (var name in nodeNames) {
      final nodeCpmData = cpmData[name] ?? NodeData();
      nodesMap[name] = gv.Node(_buildNodeWidget(name, nodeCpmData));
      gvGraph.addNode(nodesMap[name]!);
    }

    logicGraph.forEach((node, neighbors) {
      neighbors.keys.forEach((neighbor) {
        if (nodesMap.containsKey(node) && nodesMap.containsKey(neighbor)) {
          final isCritical =
              (cpmData[node]?.slack == 0) && (cpmData[neighbor]?.slack == 0);
          gvGraph.addEdge(
            nodesMap[node]!,
            nodesMap[neighbor]!,
            paint: Paint()
              ..color = isCritical ? Colors.redAccent : Colors.grey
              ..strokeWidth = isCritical ? 2.5 : 1.5,
          );
        }
      });
    });

    graphView = gvGraph;
  }

  Widget _buildNodeWidget(String name, NodeData data) {
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
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: isCritical ? Colors.red.shade900 : Colors.indigo.shade800,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ),
          const Divider(height: 10, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCpmValue("IC", data.es),
              _buildCpmValue("TC", data.ef),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCpmValue("IL", data.ls),
              _buildCpmValue("TL", data.lf),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCpmValue(String label, int value) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        Text(value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  void _showAlertDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              child: const Text("OK"),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
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

// --- PUNTO DE ENTRADA Y WIDGETS DE LA UI ---
void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => GraphState(),
      child: const CriticalPathApp(),
    ),
  );
}

class CriticalPathApp extends StatelessWidget {
  const CriticalPathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Analizador de Rutas de proyecto, Israel Andres Rosales',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
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
  // --- NUEVO DIÁLOGO DE CONFIRMACIÓN ---
  Future<void> _showResetConfirmationDialog(
      BuildContext context, GraphState state) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // El usuario debe tocar un botón para cerrar
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Reseteo'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    '¿Estás seguro de que quieres borrar todos los datos del grafo?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
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
    return Consumer<GraphState>(
      builder: (context, state, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Panel de Entrada',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                const Row(
                  children: [
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
                  ],
                ),
                const Divider(),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: state.connections.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                              child: _buildTextField(
                                  state.connections[index].originController)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _buildTextField(state
                                  .connections[index].destinationController)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _buildTextField(
                                  state.connections[index].durationController,
                                  isNumber: true)),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => state.removeConnection(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir Fila'),
                    onPressed: state.addConnection,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                        child: _buildLabeledTextField(
                            'Nodo Inicial', state.startNodeController)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _buildLabeledTextField(
                            'Nodo Final', state.endNodeController)),
                  ],
                ),
                const SizedBox(height: 24),
                // --- NUEVO ROW PARA LOS BOTONES DE ACCIÓN ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Botón de Resetear
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Resetear'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        textStyle: Theme.of(context).textTheme.titleMedium,
                      ),
                      onPressed: () =>
                          _showResetConfirmationDialog(context, state),
                    ),
                    const SizedBox(width: 16),
                    // Botón de Calcular
                    ElevatedButton.icon(
                      icon: const Icon(Icons.calculate),
                      label: const Text('Calcular Rutas'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        textStyle: Theme.of(context).textTheme.titleMedium,
                      ),
                      onPressed: () => state.calculatePaths(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller,
      {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _buildLabeledTextField(
      String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildTextField(controller),
      ],
    );
  }
}

class _GraphVisualizer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Consumer<GraphState>(
        builder: (context, state, child) {
          return Container(
            padding: const EdgeInsets.all(16.0),
            height: 400,
            child: state.graphView.nodeCount() == 0
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.share, size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text('Visualización del Grafo',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        const Text(
                            "Presiona 'Calcular Rutas' para ver el grafo.",
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : InteractiveViewer(
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(100),
                    minScale: 0.01,
                    maxScale: 5.6,
                    child: gv.GraphView(
                      graph: state.graphView,
                      algorithm:
                          gv.FruchtermanReingoldAlgorithm(iterations: 200),
                      paint: Paint()
                        ..color = Colors.grey
                        ..strokeWidth = 1
                        ..style = PaintingStyle.stroke,
                      builder: (gv.Node node) {
                        return node.data as Widget;
                      },
                    ),
                  ),
          );
        },
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

  Widget _buildResultRow(String label, String result) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(child: Text(result)),
      ],
    );
  }
}
