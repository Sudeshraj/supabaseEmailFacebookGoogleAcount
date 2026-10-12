import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReduceSalonsScreen extends StatefulWidget {
  final String ownerId;
  final int currentCount;
  final int targetCount;

  const ReduceSalonsScreen({
    super.key,
    required this.ownerId,
    required this.currentCount,
    required this.targetCount,
  });

  @override
  State<ReduceSalonsScreen> createState() => _ReduceSalonsScreenState();
}

class _ReduceSalonsScreenState extends State<ReduceSalonsScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _salons = [];
  final Set<int> _selectedForDeactivation = {};
  bool _loading = true;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSalons();
  }

  Future<void> _loadSalons() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _supabase
          .from('salons')
          .select('id, name, address, logo_url, is_active')
          .eq('owner_id', widget.ownerId)
          .eq('is_active', true)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _salons = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int get _mustDeactivate => widget.currentCount - widget.targetCount;

  int get _remaining =>
      widget.currentCount - _selectedForDeactivation.length;

  bool get _canProceed =>
      _selectedForDeactivation.length >= _mustDeactivate &&
      _remaining <= widget.targetCount;

  Future<void> _deactivateSelected() async {
    if (!_canProceed) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Salons?'),
        content: Text(
          'You are about to deactivate ${_selectedForDeactivation.length} '
          'salon(s).\n\n'
          'Deactivated salons will no longer be visible to customers. '
          'Their data (appointments, services, etc.) will be preserved and '
          'you can reactivate them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processing = true);

    try {
      await _supabase
          .from('salons')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .inFilter('id', _selectedForDeactivation.toList())
          .eq('owner_id', widget.ownerId);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to deactivate: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reduce Salons'),
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_processing)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to load salons: $_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadSalons,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final remaining = _mustDeactivate - _selectedForDeactivation.length;

    return Column(
      children: [
        // Info banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.amber[50],
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber[800]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remaining > 0
                          ? 'Deactivate $remaining more salon(s)'
                          : 'Ready to proceed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber[900],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Target plan allows ${widget.targetCount} salon(s). '
                      'You currently have ${widget.currentCount}.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.amber[900],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _salons.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.store_outlined,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No active salons found',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _salons.length,
                  itemBuilder: (context, index) {
                    final salon = _salons[index];
                    final id = salon['id'] as int;
                    final selected = _selectedForDeactivation.contains(id);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: selected ? Colors.red[50] : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: selected ? Colors.red : Colors.grey[300]!,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: CheckboxListTile(
                        value: selected,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedForDeactivation.add(id);
                            } else {
                              _selectedForDeactivation.remove(id);
                            }
                          });
                        },
                        title: Text(
                          salon['name'] as String? ?? 'Unnamed Salon',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          salon['address'] as String? ?? 'No address',
                          style: const TextStyle(fontSize: 12),
                        ),
                        secondary: salon['logo_url'] != null
                            ? CircleAvatar(
                                backgroundImage:
                                    NetworkImage(salon['logo_url'] as String),
                              )
                            : const CircleAvatar(
                                child: Icon(Icons.store),
                              ),
                        activeColor: Colors.red,
                      ),
                    );
                  },
                ),
        ),

        // Bottom action bar
        SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Selected: ${_selectedForDeactivation.length}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    if (_canProceed)
                      const Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.green, size: 18),
                          SizedBox(width: 4),
                          Text(
                            'Ready',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Need $remaining more',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canProceed ? _deactivateSelected : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Deactivate Selected Salons',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}