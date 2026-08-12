class FieldModel {
  final String id;
  final String name;
  final String location;
  final double areaHectares;
  final String growthStage;
  final int cropAgeDap;
  final String plantingDate;
  final String imageUrl;

  const FieldModel({
    required this.id,
    required this.name,
    required this.location,
    required this.areaHectares,
    required this.growthStage,
    required this.cropAgeDap,
    required this.plantingDate,
    required this.imageUrl,
  });

  static const defaultField = FieldModel(
    id: 'bayani_01',
    name: 'Bayani Cornfield',
    location: 'Brgy. Poblacion II, Piat',
    areaHectares: 2.50,
    growthStage: 'V6',
    cropAgeDap: 42,
    plantingDate: 'May 10, 2025',
    imageUrl:
        'https://images.unsplash.com/photo-1500382017468-9049fed747ef?auto=format&fit=crop&w=800&q=80',
  );
}
