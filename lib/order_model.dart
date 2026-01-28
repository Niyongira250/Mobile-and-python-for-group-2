class OrderModel {
  final String restaurant;
  final List<List<String>> items;
  final String total;

  OrderModel({
    required this.restaurant,
    required this.items,
    required this.total,
  });
}
