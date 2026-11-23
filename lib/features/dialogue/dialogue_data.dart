class DL {
  const DL(this.speaker, this.text);
  final String speaker;
  final String text;
}

const _will = 'Mr. Will';
const _ho = 'Hoross';

const Map<String, List<DL>> kDialogue = {
  'intro': [
    DL(_ho, 'Another morning in New Merrci. Mr. Will always has work for Gromson.'),
    DL(_ho, "I should visit his house. It's marked on my map."),
  ],
  'will_busy': [DL(_will, "You already have a job, Hoross. Check your map and get moving.")],
  'will_none': [DL(_will, 'No more jobs right now. Enjoy a quiet day in New Merrci.')],
  'm1_offer': [
    DL(_will, 'Hoross, good timing. Mr. Frank never came home last night.'),
    DL(_will, 'Yellwo took him. A lookout saw a yellow van heading to their warehouse.'),
    DL(_ho, "Frank wouldn't hurt anybody. Where's the warehouse?"),
    DL(_will, "East side of the city. I've marked it on your map. Bring him back safe. There's \$100 in it."),
  ],
  'm1_guard': [
    DL('Yellwo Guard', 'This is Yellwo ground. Turn around, green boy.'),
    DL(_ho, "I'm only here for Mr. Frank. Step aside and nobody gets hurt."),
    DL('Yellwo Guard', "Tell the boss we saw nothing. I'm out of here!"),
  ],
  'm1_frank': [
    DL('Mr. Frank', "Hoross! I knew Gromson wouldn't forget me."),
    DL(_ho, "Stay close, Mr. Frank. I'm taking you to Gromson HQ."),
    DL('Mr. Frank', "Lead the way. I'll be right behind you."),
  ],
  'm1_done': [
    DL('Mr. Frank', 'Safe at last. I owe you one, Hoross.'),
    DL('$_will (call)', 'Good work. Come see me when you want the next job.'),
  ],
  'm2_offer': [
    DL(_will, 'Bad news. Johnson from Yellwo stole a crate of our supplies.'),
    DL(_will, "He's driving a yellow van around town. I've marked his last known spot."),
    DL(_ho, "I'll catch him."),
    DL(_will, "Don't wreck anything you can't pay for. The reward is \$100."),
  ],
  'm2_catch': [
    DL('Johnson', 'How did you keep up with my van?!'),
    DL(_ho, 'The ride is over, Johnson. Pull over.'),
    DL('Johnson', "Okay, okay! I give up. The crate is in the back."),
  ],
  'm2_supplies': [
    DL(_ho, 'Let me see... the whole crate is here.'),
    DL('Johnson', 'Take it. Tell Yellwo I am done with this job.'),
  ],
  'm2_done': [
    DL('$_will (call)', 'The supplies are back where they belong. Nice driving, Hoross.'),
  ],
  'm3_offer': [
    DL(_will, 'Ariss has been waiting at the police station since morning.'),
    DL(_will, 'Some mix-up over a parking ticket. Pick her up and take her home.'),
    DL(_ho, 'Sounds easy enough.'),
    DL(_will, 'That is \$100 for your trouble.'),
  ],
  'm3_officer': [
    DL('Officer Dale', "You're here for Ariss? She's been telling everyone about her cat for an hour."),
    DL(_ho, 'That sounds like her. Can I take her?'),
    DL('Officer Dale', "Paperwork's done. She's free to go. Drive safe."),
  ],
  'm3_ariss': [
    DL('Ariss', 'Finally! Hoross, I thought nobody was coming.'),
    DL(_ho, "Mr. Will sent me. I'll take you home."),
    DL('Ariss', 'Good. And no more police stations today, please.'),
  ],
  'm3_done': [
    DL('Ariss', 'Home sweet home! Thanks, Hoross.'),
    DL('$_will (call)', 'That is all three jobs done. New Merrci is a little safer today.'),
  ],
  'frank_idle': [DL('Mr. Frank', 'Please... get me out of here.')],
  'ariss_idle': [DL('Ariss', "I'm just waiting for my ride. Nice jacket, by the way.")],
  'civ': [DL('Civilian', 'Lovely day in New Merrci, is it not?')],
  'gromson': [DL('Gromson Member', 'Green stands for New Merrci. Stay safe out there, Hoross.')],
  'yellwo': [DL('Yellwo Member', "You're a long way from home, Gromson.")],
  'cop': [DL('Officer', 'Keep it legal out there, citizen.')],
};
