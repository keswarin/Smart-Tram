class Building {
  final String id;
  final String name;

  Building({
    required this.id,
    required this.name,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'] ?? json['buildingId'] ?? '',
      name: json['name'] ?? json['buildingName'] ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}
