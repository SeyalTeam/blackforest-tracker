import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class DailyTasksPage extends StatefulWidget {
  const DailyTasksPage({super.key});

  @override
  State<DailyTasksPage> createState() => _DailyTasksPageState();
}

class _DailyTasksPageState extends State<DailyTasksPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tasks = [];
  final Set<String> _togglingTaskIds = {};
  String _filter = 'all'; // 'all' | 'pending' | 'completed'

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance.fetchMyDailyTasks();
      if (res['success'] == true && res['tasks'] is List) {
        if (mounted) {
          setState(() {
            _tasks = List<Map<String, dynamic>>.from(
              (res['tasks'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading daily tasks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load tasks: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleTask(String taskId, bool currentCompleted) async {
    if (_togglingTaskIds.contains(taskId)) return;

    final targetCompleted = !currentCompleted;

    // Optimistic UI update
    setState(() {
      _togglingTaskIds.add(taskId);
      final index = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
      if (index != -1) {
        _tasks[index]['completed'] = targetCompleted;
        if (targetCompleted) {
          _tasks[index]['completedAt'] = DateTime.now().toIso8601String();
        } else {
          _tasks[index]['completedAt'] = null;
        }
      }
    });

    try {
      final res = await ApiService.instance.toggleDailyTask(
        taskId: taskId,
        completed: targetCompleted,
      );
      if (res['success'] != true) {
        // Revert on failure
        if (mounted) {
          setState(() {
            final index = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
            if (index != -1) {
              _tasks[index]['completed'] = currentCompleted;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling task: $e');
      if (mounted) {
        setState(() {
          final index = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
          if (index != -1) {
            _tasks[index]['completed'] = currentCompleted;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _togglingTaskIds.remove(taskId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _tasks.where((t) => t['completed'] == true).length;
    final totalCount = _tasks.length;
    final pendingCount = totalCount - completedCount;

    List<Map<String, dynamic>> displayedTasks = _tasks;
    if (_filter == 'pending') {
      displayedTasks = _tasks.where((t) => t['completed'] != true).toList();
    } else if (_filter == 'completed') {
      displayedTasks = _tasks.where((t) => t['completed'] == true).toList();
    }

    final todayFormatted = DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Daily Work Tasks',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchTasks,
            tooltip: 'Refresh tasks',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTasks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. DATE & SUMMARY CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E3192).withValues(alpha: 0.25),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          todayFormatted,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Task Progress',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              totalCount == 0
                                  ? '0 Tasks'
                                  : '$completedCount / $totalCount Completed',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            totalCount == 0
                                ? '0%'
                                : '${((completedCount / totalCount) * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: totalCount > 0 ? (completedCount / totalCount) : 0.0,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. FILTER TABS (All | Pending | Completed)
              if (totalCount > 0)
                Row(
                  children: [
                    _buildFilterChip('All', 'all', totalCount),
                    const SizedBox(width: 8),
                    _buildFilterChip('Pending', 'pending', pendingCount),
                    const SizedBox(width: 8),
                    _buildFilterChip('Completed', 'completed', completedCount),
                  ],
                ),

              const SizedBox(height: 16),

              // 3. TASK LIST OR EMPTY STATE
              if (_isLoading && _tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF2E3192)),
                  ),
                )
              else if (_tasks.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.task_alt,
                          size: 40,
                          color: Color(0xFF2E3192),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'No Tasks Found',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'There are no active tasks assigned to your role or profile today.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              else if (displayedTasks.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'No ${_filter} tasks',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedTasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final task = displayedTasks[index];
                    final taskId = task['id']?.toString() ?? '';
                    final isCompleted = task['completed'] == true;
                    final isToggling = _togglingTaskIds.contains(taskId);
                    final title = task['title']?.toString() ?? 'Task';
                    final desc = task['description']?.toString() ?? '';
                    final priority =
                        task['priority']?.toString().toLowerCase() ?? 'medium';
                    final assignedRole = task['assignedRole']?.toString() ?? '';
                    final completedAtStr = task['completedAt']?.toString();

                    String? formattedTime;
                    if (completedAtStr != null && completedAtStr.isNotEmpty) {
                      try {
                        final dt = DateTime.parse(completedAtStr).toLocal();
                        formattedTime = DateFormat('hh:mm a').format(dt);
                      } catch (_) {}
                    }

                    Color priorityBg = Colors.grey[100]!;
                    Color priorityFg = Colors.grey[700]!;
                    if (priority == 'urgent') {
                      priorityBg = Colors.red[50]!;
                      priorityFg = Colors.red[700]!;
                    } else if (priority == 'high') {
                      priorityBg = Colors.orange[50]!;
                      priorityFg = Colors.orange[800]!;
                    } else if (priority == 'low') {
                      priorityBg = Colors.blue[50]!;
                      priorityFg = Colors.blue[700]!;
                    }

                    return InkWell(
                      onTap: isToggling ? null : () => _toggleTask(taskId, isCompleted),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green.withValues(alpha: 0.04)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(
                            color: isCompleted
                                ? Colors.green.withValues(alpha: 0.35)
                                : Colors.grey[200]!,
                            width: isCompleted ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: isToggling
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Checkbox(
                                        value: isCompleted,
                                        activeColor: Colors.green,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        onChanged: isToggling
                                            ? null
                                            : (_) => _toggleTask(taskId, isCompleted),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isCompleted
                                          ? Colors.grey[500]
                                          : Colors.black87,
                                      decoration: isCompleted
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                    ),
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      desc,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey[600],
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: priorityBg,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          priority.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: priorityFg,
                                          ),
                                        ),
                                      ),
                                      if (assignedRole.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            assignedRole.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple[700],
                                            ),
                                          ),
                                        ),
                                      if (isCompleted && formattedTime != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Done at $formattedTime',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.green[800],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E3192) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF2E3192) : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
