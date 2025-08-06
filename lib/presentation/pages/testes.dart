import 'package:flutter/material.dart';

class PaginaComSliverEFixoNaBase extends StatelessWidget {
  const PaginaComSliverEFixoNaBase({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Conteúdo scrollável
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 200,
                flexibleSpace: const FlexibleSpaceBar(
                  title: Text('Título'),
                  background: FlutterLogo(),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ListTile(
                    title: Text('Item $index'),
                  ),
                  childCount: 30,
                ),
              ),
              // Espaço extra no fim da lista
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ),

          // Componente fixo na base
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 16,
                right: 16,
              ),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Digite algo...',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
