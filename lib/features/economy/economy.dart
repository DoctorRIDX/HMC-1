/// In-game dollars. Starting money is $0.
class Wallet {
  Wallet([this.money = 0]);
  int money;

  void add(int amount) {
    if (amount > 0) money += amount;
  }

  bool spend(int amount) {
    if (amount <= 0 || amount > money) return false;
    money -= amount;
    return true;
  }
}

class Inventory {
  Inventory([Map<String, int>? start]) : items = {...?start};
  final Map<String, int> items;

  int count(String id) => items[id] ?? 0;
  bool has(String id) => count(id) > 0;

  void add(String id, [int n = 1]) {
    if (n > 0) items[id] = count(id) + n;
  }

  bool remove(String id, [int n = 1]) {
    if (n <= 0 || count(id) < n) return false;
    final left = count(id) - n;
    if (left == 0) {
      items.remove(id);
    } else {
      items[id] = left;
    }
    return true;
  }
}
