/// Best-effort category from an expense's description, so totals stay useful
/// without anyone picking one. Shared by the expense form, the UPI pop-up and
/// receipt scanning.
library;

/// Keyword lists, checked in this order (the first match wins). Words match
/// at word starts ("taxi" fires on "taxis", "ola" doesn't on "cola"); a
/// trailing `\b` makes a word whole-only ("bus\b" skips "business").
/// Specific bills come before Food so "water bill" isn't drinking water.
const _keywords = <String, List<String>>{
  'Utilities': [
    'electricity', 'electric bill', 'power bill', 'light bill', 'wifi', 'wi-fi', 'internet', 'broadband',
    'recharge', 'prepaid', 'postpaid', 'jio', 'airtel', 'bsnl', 'dth', 'tata play', 'lpg', 'gas cylinder',
    'cylinder', 'water bill', 'torrent power', 'mgvcl', 'ugvcl', 'dgvcl', 'pgvcl', 'adani electricity',
  ],
  'Rent': ['rent\\b', 'rents\\b', 'house rent', 'maintenance', 'deposit', 'landlord', 'brokerage', 'pg\\b'],
  'Fuel': [
    'petrol', 'diesel', 'fuel', 'cng', 'indian oil', 'iocl', 'bpcl', 'hpcl', 'bharat petroleum',
    'hindustan petroleum', 'nayara', 'shell\\b', 'filling station', 'petrol pump', 'ev charging',
  ],
  'Groceries': [
    'grocery', 'groceries', 'kirana', 'supermarket', 'dmart', 'd-mart', 'd mart', 'bigbasket', 'big basket',
    'blinkit', 'zepto', 'instamart', 'jiomart', 'reliance fresh', 'more supermarket', 'vegetable', 'sabzi',
    'sabji', 'fruit', 'milk', 'dairy', 'amul', 'provision', 'atta', 'rice\\b', 'eggs\\b',
  ],
  'Food': [
    'zomato', 'swiggy', 'restaurant', 'cafe', 'café', 'food', 'dhaba', 'pizza', 'bakery', 'chai', 'tea\\b',
    'coffee', 'kitchen', 'lunch', 'dinner', 'breakfast', 'brunch', 'snack', 'thali', 'dhokla', 'fafda', 'khaman',
    'jalebi', 'juice', 'ice cream', 'icecream', 'sweets', 'mithai', 'water\\b', 'meal', 'biryani', 'paan',
    'kulfi', 'lassi', 'drink', 'beer', 'bar\\b', 'pub\\b', 'dosa', 'idli', 'samosa', 'pav', 'vada', 'maggi',
    'domino', 'kfc', 'mcdonald', 'burger', 'subway', 'haldiram', 'canteen', 'mess\\b', 'tiffin', 'chaat',
    'pani puri', 'golgappa', 'bhel', 'gathiya', 'khakhra', 'handvo', 'undhiyu', 'starbucks', 'barbeque',
    'bbq', 'buffet', 'party',
  ],
  'Transport': [
    'uber', 'ola\\b', 'rapido', 'irctc', 'railway', 'train', 'redbus', 'bus\\b', 'buses', 'gsrtc', 'volvo',
    'metro', 'indigo', 'air india', 'akasa', 'spicejet', 'airline', 'flight', 'airport', 'cab\\b', 'cabs\\b',
    'taxi', 'auto\\b', 'rickshaw', 'toll', 'fastag', 'parking', 'ferry', 'travels', 'car rental', 'car hire',
    'bike rent', 'scooty', 'vande bharat', 'blablacar',
  ],
  'Stay': [
    'oyo', 'airbnb', 'hotel', 'resort', 'stay', 'lodge', 'room\\b', 'rooms\\b', 'hostel', 'dharamshala',
    'guest house', 'guesthouse', 'homestay', 'makemytrip', 'goibibo', 'booking.com', 'agoda', 'check-in',
    'checkin', 'villa', 'tent',
  ],
  'Activities': [
    'ticket', 'bookmyshow', 'museum', 'safari', 'entry', 'park\\b', 'temple', 'darshan', 'boat', 'ropeway',
    'tour', 'guide', 'garba', 'show\\b', 'shows\\b', 'movie', 'cinema', 'pvr', 'inox', 'fort', 'zoo', 'camel',
    'ride', 'statue', 'beach', 'trek', 'rafting', 'paragliding', 'scuba', 'water park', 'game', 'bowling',
  ],
  'Shopping': [
    'amazon', 'flipkart', 'myntra', 'meesho', 'ajio', 'nykaa', 'shopping', 'mall\\b', 'clothes', 'shirt',
    'tshirt', 't-shirt', 'jeans', 'saree', 'sari\\b', 'kurta', 'dupatta', 'bandhani', 'chaniya', 'shoes',
    'slipper', 'gift', 'souvenir', 'handicraft', 'jewel', 'bag\\b', 'watch\\b', 'electronics', 'croma',
  ],
};

final _patterns = {
  for (final e in _keywords.entries) e.key: RegExp('\\b(${e.value.join('|')})', caseSensitive: false),
};

/// The category [description] points to, else what [payee] (a UPI payee
/// name) points to, else 'Other'. The description wins, so a "taxi" paid to
/// a food-delivery account is still Transport.
String guessCategory(String description, {String? payee}) {
  for (final text in [description, if (payee != null) payee]) {
    for (final e in _patterns.entries) {
      if (e.value.hasMatch(text)) return e.key;
    }
  }
  return 'Other';
}

/// The category after the description changes. While [auto] (nobody has
/// picked one, or the last change came from the description) it follows the
/// guess. After a manual pick, the pick stays unless the new description
/// clearly points somewhere else, which hands control back to the guess.
({String category, bool auto}) followDescription({
  required String current,
  required bool auto,
  required String description,
  String? payee,
}) {
  final guess = guessCategory(description, payee: payee);
  if (auto || guess != 'Other') return (category: guess, auto: true);
  return (category: current, auto: false);
}
