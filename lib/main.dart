/*
* ======================================================================
* NOTA IMPORTANTE: Si ves errores como "Target of URI doesn't exist"
* o "Undefined class 'Digraph'", sigue estos pasos:
*
* 1. Guarda este archivo (main.dart).
* 2. En la terminal de VS Code, ejecuta el comando: flutter pub get
* 3. Reinicia VS Code por completo (cierra y vuelve a abrir).
*
* Esto forzará al editor a reconocer los paquetes que hemos añadido.
* ======================================================================
*/
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:graph/graph.dart';
import 'package:graphview/GraphView.dart' as gv;
import 'dart:math';

// --- ESTRUCTURAS DE DATOS ---

class Connection {
  final TextEditingController originController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  final TextEditingController durationController = TextEditingController();
}

// Clase para almacenar los datos calculados de la ruta crítica para cada nodo.
class NodeData {
  int es = 0; // Earliest Start (Inicio Cercano)
  int ef = 0; // Earliest Finish (Término Cercano)
  int ls = 0; // Latest Start (Inicio Lejano)
  int lf = 0; // Latest Finish (Término Lejano)
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

  // --- LÓGICA DE CÁLCULO PRINCIPAL ---
  void calculatePaths(BuildContext context) {
    final graph = Digraph<String, int>();
    final allNodeNames = <String>{};

    for (var conn in connections) {
      final origin = conn.originController.text.trim();
      final dest = conn.destinationController.text.trim();
      final durationStr = conn.durationController.text.trim();

      if (origin.isEmpty || dest.isEmpty || durationStr.isEmpty) {
        _showAlertDialog(
          context,
          'Error',
          'Todos los campos de conexión deben estar llenos.',
        );
        return;
      }

      final duration = int.tryParse(durationStr);
      if (duration == null) {
        _showAlertDialog(
          context,
          'Error',
          'La duración debe ser un número entero.',
        );
        return;
      }

      graph.addEdge(origin, dest, value: duration);
      allNodeNames.add(origin);
      allNodeNames.add(dest);
    }

    final startNode = startNodeController.text.trim();
    final endNode = endNodeController.text.trim();

    if (startNode.isEmpty || endNode.isEmpty) {
      _showAlertDialog(
        context,
        'Error',
        'Debe especificar un nodo inicial y final.',
      );
      return;
    }

    // Calcular ruta corta
    try {
      final shortest = graph.shortestPath(startNode, endNode);
      final shortestDuration = _calculatePathDuration(graph, shortest);
      shortestPathResult =
          '${shortest.join(' → ')} (Duración: $shortestDuration semanas)';
    } catch (e) {
      shortestPathResult = 'No se encontró una ruta.';
    }

    // Calcular ruta larga (crítica) y datos CPM
    try {
      final allPaths = _findAllPaths(graph, startNode, endNode);
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

        // ¡NUEVO! Calcular datos CPM
        cpmData = _calculateCPM(graph, allNodeNames, startNode, maxDuration);

        _buildGraphView(graph, allNodeNames, longestPath);
      }
    } catch (e) {
      longestPathResult = 'No se encontró una ruta.';
    }

    notifyListeners();
  }

  // --- MÉTODOS DE CÁLCULO CPM (NUEVO) ---

  Map<String, NodeData> _calculateCPM(
    Digraph<String, int> graph,
    Set<String> allNodes,
    String startNode,
    int projectDuration,
  ) {
    Map<String, NodeData> data = {for (var node in allNodes) node: NodeData()};
    var topologicalSort = graph.topologicalSort();

    // Forward Pass (ES, EF)
    for (var node in topologicalSort) {
      if (node == startNode) {
        data[node]!.es = 0;
      } else {
        var predecessors = graph.predecessors(node);
        data[node]!.es = predecessors.map((p) => data[p]!.ef).reduce(max);
      }
      // La duración de una "actividad" es la duración de la arista que LLEGA a ella.
      // Esto es una simplificación. En CPM real, las actividades son las aristas.
      // Aquí, asumimos que la duración es del nodo.
      var incomingEdges = graph.predecessors(node);
      var duration = incomingEdges.isNotEmpty
          ? graph.edgeValue(incomingEdges.first, node)!
          : 0;
      if (node == startNode)
        duration =
            0; // El nodo de inicio no tiene duración de actividad previa.

      data[node]!.ef = data[node]!.es + duration;
    }

    // Backward Pass (LF, LS)
    var endNode = topologicalSort.last;
    data[endNode]!.lf = data[endNode]!.ef; // O projectDuration

    for (var node in topologicalSort.reversed) {
      if (node == endNode) {
        data[node]!.lf = data[node]!.ef;
      } else {
        var successors = graph.edges(node);
        data[node]!.lf = successors.map((s) => data[s]!.ls).reduce(min);
      }
      var incomingEdges = graph.predecessors(node);
      var duration = incomingEdges.isNotEmpty
          ? graph.edgeValue(incomingEdges.first, node)!
          : 0;
      if (node == startNode) duration = 0;

      data[node]!.ls = data[node]!.lf - duration;
      data[node]!.slack = data[node]!.ls - data[node]!.es;
    }

    return data;
  }

  // --- MÉTODOS AUXILIARES ---

  int _calculatePathDuration(Digraph<String, int> graph, List<String> path) {
    int total = 0;
    for (int i = 0; i < path.length - 1; i++) {
      total += graph.edgeValue(path[i], path[i + 1])!;
    }
    return total;
  }

  List<List<String>> _findAllPaths(
    Digraph<String, int> graph,
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

      final neighbors = List<String>.from(graph.edges(currentNode));
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
    Digraph<String, int> logicGraph,
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
      for (var neighbor in neighbors) {
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

    graphView = gvGraph;
    builder
      ..siblingSeparation = (25)
      ..levelSeparation = (50)
      ..subtreeSeparation = (25)
      ..orientation = (gv.BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT);
  }

  // --- WIDGETS DE VISUALIZACIÓN (NUEVO DISEÑO) ---

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
                fontSize: 16,
              ),
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
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
        ),
        Text(
          value.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
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

// --- PUNTO DE ENTRADA Y WIDGETS DE LA UI (SIN CAMBIOS) ---
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
      title: 'Analizador de Rutas de Proyecto',
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
                Text(
                  'Panel de Entrada',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Origen',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Destino',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Duración (sem)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
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
                              state.connections[index].originController,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTextField(
                              state.connections[index].destinationController,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTextField(
                              state.connections[index].durationController,
                              isNumber: true,
                            ),
                          ),
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
                        'Nodo Inicial',
                        state.startNodeController,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildLabeledTextField(
                        'Nodo Final',
                        state.endNodeController,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.calculate),
                    label: const Text('Calcular Rutas'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      textStyle: Theme.of(context).textTheme.titleMedium,
                    ),
                    onPressed: () => state.calculatePaths(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField(
    TextEditingController controller, {
    bool isNumber = false,
  }) {
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
    String label,
    TextEditingController controller,
  ) {
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
                        Text(
                          'Visualización del Grafo',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Presiona 'Calcular Rutas' para ver el grafo.",
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
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
                      algorithm: gv.BuchheimWalkerAlgorithm(
                        state.builder,
                        gv.TreeEdgeRenderer(state.builder),
                      ),
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
            Text(
              'Panel de Resultados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildResultRow('Ruta más Corta:', state.shortestPathResult),
            const SizedBox(height: 8),
            _buildResultRow(
              'Ruta más Larga (Crítica):',
              state.longestPathResult,
            ),
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
