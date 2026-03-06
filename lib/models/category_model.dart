import 'package:flutter/material.dart';

class CategoryModel {
  final int id;
  final String name;
  final String? description;
  final String iconName;
  final String? colorHex;
  final int displayOrder;
  final bool isActive;

  CategoryModel({
    required this.id,
    required this.name,
    this.description,
    required this.iconName,
    this.colorHex,
    required this.displayOrder,
    required this.isActive,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      iconName: json['icon_name'] as String,
      colorHex: json['color'] as String?,
      displayOrder: json['display_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon_name': iconName,
      'color': colorHex,
      'display_order': displayOrder,
      'is_active': isActive,
    };
  }

  // Helper to get IconData from iconName
  IconData get icon {
    switch (iconName) {
      case 'content_cut':
        return Icons.content_cut;
      case 'face':
        return Icons.face;
      case 'face_retouching_natural':
        return Icons.face_retouching_natural;
      case 'spa':
        return Icons.spa;
      case 'handshake':
        return Icons.handshake;
      case 'build_circle_outlined':
        return Icons.build_circle_outlined;
      case 'brush':
        return Icons.brush;
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'sports_kabaddi':
        return Icons.sports_kabaddi;
      default:
        return Icons.category_outlined;
    }
  }

  // Get color from hex string
  Color? get color {
    if (colorHex == null) return null;
    try {
      return Color(int.parse(colorHex!.replaceFirst('#', '0xFF')));
    } catch (e) {
      return null;
    }
  }
}