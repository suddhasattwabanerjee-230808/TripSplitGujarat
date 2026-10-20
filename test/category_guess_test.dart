import 'package:flutter_test/flutter_test.dart';
import 'package:trip_split_gujarat/category_guess.dart';

void main() {
  test('every built-in category can be guessed', () {
    expect(guessCategory('Dinner at Manek Chowk'), 'Food');
    expect(guessCategory('DMart run'), 'Groceries');
    expect(guessCategory('Hotel Hyatt, 2 nights'), 'Stay');
    expect(guessCategory('Flat rent for October'), 'Rent');
    expect(guessCategory('Uber to the airport'), 'Transport');
    expect(guessCategory('Petrol at HP'), 'Fuel');
    expect(guessCategory('Bandhani dupattas'), 'Shopping');
    expect(guessCategory('Airtel wifi bill'), 'Utilities');
    expect(guessCategory('Rani ki Vav tickets'), 'Activities');
    expect(guessCategory('asdf'), 'Other');
  });

  test('word starts and whole words avoid false matches', () {
    expect(guessCategory('Business lunch'), 'Food'); // "bus" doesn't fire on "business"
    expect(guessCategory('Cola'), 'Other'); // "ola" doesn't fire inside "cola"
    expect(guessCategory('Water bill'), 'Utilities'); // a bill, not drinking water
    expect(guessCategory('Bottle of water'), 'Food');
    expect(guessCategory('Team outing'), 'Other'); // "tea" is whole-word only
  });

  test('the description beats the UPI payee', () {
    expect(guessCategory('Taxi home', payee: 'SWIGGY'), 'Transport');
    expect(guessCategory('', payee: 'SWIGGY'), 'Food');
    expect(guessCategory('xyz', payee: 'Indian Oil'), 'Fuel');
  });

  test('the category follows the description, even after a manual pick', () {
    // Auto: follows every change, including back to Other.
    var next = followDescription(current: 'Other', auto: true, description: 'pizza');
    expect(next, (category: 'Food', auto: true));
    next = followDescription(current: 'Food', auto: true, description: 'pizza and cab');
    expect(next.category, 'Food'); // first match in priority order
    next = followDescription(current: 'Food', auto: true, description: 'qwerty');
    expect(next, (category: 'Other', auto: true));

    // Manual pick: kept while the description says nothing clear...
    next = followDescription(current: 'Shopping', auto: false, description: 'for mom');
    expect(next, (category: 'Shopping', auto: false));
    // ...and replaced (back to auto) when it clearly points elsewhere.
    next = followDescription(current: 'Shopping', auto: false, description: 'for mom, taxi');
    expect(next, (category: 'Transport', auto: true));
  });
}
