/// What the panel says while the AI is searching or doing something for the customer, so a wait never looks like a freeze.
/// One word at a time, changing every second or so.
const workingWords = <String>[
  'Vibing',
  'Wheezing',
  'Pondering',
  'Noodling',
  'Brewing',
  'Cooking',
  'Untangling',
  'Conjuring',
  'Rummaging',
  'Percolating',
  'Tinkering',
  'Scheming',
  'Mulling',
  'Whirring',
  'Hustling',
  'Digging',
];

/// The word for a tick. [seed] makes each session start somewhere different; the same arguments always give the same word.
String workingWord(int tick, [int seed = 0]) => workingWords[(tick + seed) % workingWords.length];
