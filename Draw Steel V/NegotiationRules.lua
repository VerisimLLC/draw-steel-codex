local mod = dmhub.GetModLoading()


RegisterGameType("MCDMNegotiation")
RegisterGameType("MCDMMotivation")
RegisterGameType("MCDMPitfall")

function MCDMNegotiation.Create()
	return MCDMNegotiation.new {

		pitfalls = {},
		motivations = {},
		accepted = {},
		dialog = DeepCopy(MCDMNegotiation.dialog),

	}
end

MCDMNegotiation.interest = 2
MCDMNegotiation.patience = 3
MCDMNegotiation.switch = true
MCDMNegotiation.MaxInterest = 5
MCDMNegotiation.MaxPatience = 5


MCDMNegotiation.dialog = {

	interest = {

		"I am not interested!",
		"That's not going to sway me.",
		"Hmmm....",
		"Makes sense to me.",
		"That's an excellent point.",
		"You've given me much to consider.",


	},

	patience = {

		"BORING!",
		"This debate is tiresome.",
		"I've heard that before.",
		"I am listening...",
		"Tell me more!",
		"I am excited to hear your offer!",


	},

	offer = {

		"No, and...",
		"No.",
		"No, but...",
		"Yes, but...",
		"Yes.",
		"Yes, and...",


	},




}



MCDMNegotiation.motivations = {


	benevolence = {

		revealed = false,
		used = false,

	},
	discovery = {

		revealed = false,
		used = false,

	},
	freedom = {

		revealed = false,
		used = false,

	},

	greed = {

		revealed = false,
		used = false,

	},

	higherauthority = {

		revealed = false,
		used = false,

	},

	justice = {

		revealed = false,
		used = false,

	},
	legacy = {

		revealed = false,
		used = false,

	},
	peace = {

		revealed = false,
		used = false,

	},
	power = {

		revealed = false,
		used = false,

	},
	protection = {

		revealed = false,
		used = false,

	},
	revelry = {

		revealed = false,
		used = false,

	},
	vengence = {

		revealed = false,
		used = false,

	},

}

MCDMNegotiation.pitfalls = {


	benevolence = {

		revealed = false,
		used = false,

	},
	discovery = {

		revealed = false,
		used = false,

	},
	freedom = {

		revealed = false,
		used = false,

	},

	greed = {

		revealed = false,
		used = false,

	},

	higherauthority = {

		revealed = false,
		used = false,

	},

	justice = {

		revealed = false,
		used = false,

	},
	legacy = {

		revealed = false,
		used = false,

	},
	peace = {

		revealed = false,
		used = false,

	},
	power = {

		revealed = false,
		used = false,

	},
	protection = {

		revealed = false,
		used = false,

	},
	revelry = {

		revealed = false,
		used = false,

	},
	vengence = {

		revealed = false,
		used = false,

	},

}


MCDMMotivation.name = "Motivation"
MCDMMotivation.details = ""

MCDMPitfall.name = "Pitfall"
MCDMPitfall.details = ""


function MCDMMotivation.GetMotivations()
	return MCDMMotivation.motivations
end

function MCDMPitfall.GetPitfalls()
	return MCDMPitfall.pitfalls
end

MCDMPitfall.pitfalls = {

	benevolence = MCDMPitfall.new {
		name = "Benevolence",
		details = [[An NPC with the benevolence pitfall has a cynical view of the world, believing that no creature has a right to anything just by being alive. The idea of helping others because it is the right thing to do is a preposterous, immature, or inexperienced idea to be laughed off or snuffed out.]],

	},
	discovery = MCDMPitfall.new {

		name = "Discovery",
		details = [[An NPC with the discovery pitfall has no interest in finding new places, peoples, or ideas. It might be that the unknown scares them or makes them so uncomfortable that they'd rather remain ignorant. Alternatively, a previous pursuit of discovery might have turned out poorly for them.]],

	},

	freedom = MCDMPitfall.new {

		name = "Freedom",
		details = [[An NPC with the freedom pitfall believes that a world without authority is one in turmoil and chaos. They might even believe that they are the right person to rule, and that their ideals should be the ones that become the law of the land.]],

	},

	greed = MCDMPitfall.new {

		name = "Greed",
		details = [[An NPC with the greed pitfall has no interest in accumulating wealth or other resources, and becomes offended if anyone tries to buy their partnership. They hold their ideals above material desires.]],

	},

	higherauthority = MCDMPitfall.new {

		name = "Higher Authority",
		details = [[An NPC with the higher authority pitfall scoffs at the idea of serving another. The NPC might not believe that all people should be free, but they certainly believe that they personally shouldn't have to answer to anyone.]],

	},

	justice = MCDMPitfall.new {

		name = "Justice",
		details = [[An NPC with the justice pitfall doesn't believe that the timescape is an inherently just place, and has no interest in making it one. The world is eternal conflict, there is no such thing as justice, and anyone who thinks otherwise is a naive fool.]],

	},

	legacy = MCDMPitfall.new {

		name = "Legacy",
		details = [[An NPC with a legacy pitfall cares nothing about leaving a personal mark on the world. To them, such vain thinking is nothing but a waste of time.]],

	},

	peace = MCDMPitfall.new {

		name = "Peace",
		details = [[An NPC with the peace pitfall hates being bored. They want excitement, drama, and danger in their life. For them, there's nothing worse than the status quo.]],

	},
	power = MCDMPitfall.new {

		name = "Power",
		details = [[An NPC with the power pitfall has no interest in authority for themself. They might respect the authority of others, but they hate the thought of ruling over other people and roundly reject any suggestion of the idea.]],

	},
	protection = MCDMPitfall.new {

		name = "Protection",
		details = [[An NPC with the protection pitfall is happy to leave others to fend for themselves. They don't believe it's their responsibility to protect anyone other than themself, and might be outright disgusted at the thought of risking their life or their property to protect others.]],

	},
	revelry = MCDMPitfall.new {

		name = "Revelry",
		details = [[An NPC with the revelry pitfall sees social encounters and hedonism as a waste of time. They take pleasure only in work or in building their own skills and character. Others who suggest immature debauchery are not worth their time.]],

	},
	vengence = MCDMPitfall.new {

		name = "Vengence",
		details = [[An NPC with the vengeance pitfall believes that revenge solves nothing. They might have gained this belief firsthand, or they might simply not have the ambition to seek revenge-and they take a dim view of others who do.]],
	},


}

MCDMMotivation.motivations = {

	benevolence = MCDMMotivation.new {

		name = "Benevolence",
		details = [[An NPC with the benevolence motivation believes in sharing what they have with others. However, an NPC involved in a negotiation must be limited in their benevolence, so that they don't just give the heroes what they need. Sometimes an NPC's benevolence might extend only to a specific group of people, so that a benevolent pirate captain might share their plunder freely with the rest of their crew-but they're still plundering! Other times, an NPC's charity might be limited by the fact that they don't have much to give. A benevolent NPC might be hesitant to give the heroes help because they believe their limited resources are more necessary or could do more good somewhere else.]],

	},

	discovery = MCDMMotivation.new {

		name = "Discovery",
		details = [[An NPC with the discovery motivation wants to learn new lore, explore forgotten places, break ground with new experiments, or uncover artifacts lost to time. Their curiosity  nd quest for knowledge might be driven by a specific goal, such as seeking the cure for a rare disease or a portal to a specific far-off world. Or they could be a naturally  inquisitive person who simply wants to understand all they can about the timescape.]],


	},

	freedom = MCDMMotivation.new {

		name = "Freedom",
		details = [[An NPC with the freedom motivation wants no authority above them and desires no authority over others. They might already have personal freedom and wish to maintain that status quo, or they might wish to liberate themself or others from someone else's authority.]],


	},

	greed = MCDMMotivation.new {

		name = "Greed",
		details = [[An NPC with the greed motivation desires wealth and resources above almost anything else. Sometimes these NPCs are misers, much like wyrms who hoard coins and gems but never spend or donate them. Others flaunt their wealth, viewing it as a sign of their station in life. Greed-driven NPCs might share their wealth with a select group of people they love, such as a noble lord who indulges his children's every desire. Some NPCs might be greedy for resources other than money, such as a demon who wants to collect and devour souls, or a troll lord who hungers endlessly for the flesh of others.]],

	},


	higherauthority = MCDMMotivation.new {

		name = "Higher Authority",
		details = [[An NPC with the higher authority motivation remains staunchly loyal to a person or force they perceive as more important than themself. This higher authority could be an organization, a deity or being of great power, a formal leader such as a noble or monarch, a mystical presence or force the NPC might not fully understand, or a person the NPC sees as an informal authority figure (an older sibling, a personal hero, and so forth).]],
	},

	justice = MCDMMotivation.new {

		name = "Justice",
		details = [[An NPC with the justice motivation wants to see the righteous rewarded and the wicked punished, however subjective their sense of who or what is good and evil. A priest who venerates a god of nature might believe that all who protect plants and animals are righteous, and that those who harvest natural resources as miners and lumberjacks do must die. Having a justice motivation doesn't necessarily make an NPC kind or charitable.]],

	},

	legacy = MCDMMotivation.new {

		name = "Legacy",
		details = [[An NPC with the legacy motivation desires fame while alive and acclaim that lasts long after their death. They hope others will know and remember their deeds, great or terrible. Some of these NPCs might even seek immortality through deification or undeath, so that the eventual shedding of their mortal coil doesn't prevent them from continuing to make history.]],

	},

	peace = MCDMMotivation.new {

		name = "Peace",
		details = [[An NPC with the peace motivation wants calm in their life. Under typical circumstances, they want to be left alone to run their business, farm, kingdom, criminal empire, or whatever small slice of the timescape is theirs. Some such NPCs don't have peace and need help obtaining it, while others want their peaceful status quo to be maintained.]],

	},

	power = MCDMMotivation.new {

		name = "Power",
		details = [[An NPC with the power motivation covets the authority of others. They want to increase their influence, no matter how great it already is, and maintain their domain. They might seek power through conquering others, the collection of artifacts, or through the infusion of supernatural rituals-though why choose one method when all three together achieve the best results? Some such NPCs are world-traversing tyrants, but the petty administrators of village organizations and shrines can covet power just as hungrily.]],

	},

	protection = MCDMMotivation.new {

		name = "Protection",
		details = [[An NPC with the protection motivation has land, people, information, items, or an organization they want protected above all else. Keeping their charge safe is a duty they hold dear, and aiding in that protection earns their favor. Most people have friends or family they wish to protect, but an NPC with the protection motivation believes in doing so at any cost.]],

	},

	revelry = MCDMMotivation.new {

		name = "Revelry",
		details = [[An NPC with the revelry motivation just wants to have fun. They enjoy socializing at parties, thrill-seeking, or indulging in other hedonistic activities. Getting pleasure out of life while spending time with people they like is paramount to such NPCs.]],

	},

	vengence = MCDMMotivation.new {

		name = "Vengence",
		details = [[An NPC with the vengeance motivation wants to harm another who has hurt them. Their desire for revenge could be proportional to the harm that was inflicted upon them, or they might wish to pay back their pain with interest. In some cases, a desire for vengeance can be satisfied only by the death of another, but an NPC might wish to pay back their own suffering with embarrassment, career failure, or some other less permanent pain.]],

	},


}

--Prepped negotiator archetype used as reusable compendium content. This is
--distinct from MCDMNegotiation, which is the live negotiation created on a
--token during play. A Negotiator is the GM-authored archetype from the manual's
--"Sample Negotiators": a name, an impression score, flavor text, a description,
--and free-form named motivations and pitfalls.
NegotiatorTrait = RegisterGameType("NegotiatorTrait")
NegotiatorTrait.name = ""
NegotiatorTrait.description = ""

function NegotiatorTrait.Create(args)
    args = args or {}
    return NegotiatorTrait.new{
        name = args.name or "",
        description = args.description or "",
    }
end

Negotiator = RegisterGameType("Negotiator")
Negotiator.tableName = "negotiators"
Negotiator.name = "New Negotiator"
Negotiator.impressionScore = 1
Negotiator.flavorText = ""
Negotiator.description = ""
--ordered lists of NegotiatorTrait. Always set to fresh tables by CreateNew so
--instances never share the prototype default.
Negotiator.motivations = {}
Negotiator.pitfalls = {}

function Negotiator.CreateNew(args)
    local result = Negotiator.new{
        name = "New Negotiator",
        impressionScore = 1,
        flavorText = "",
        description = "",
        motivations = {},
        pitfalls = {},
    }
    if args then
        for k,v in pairs(args) do
            result[k] = v
        end
    end
    return result
end

--==============================================================================
-- Negotiation rules engine + live-state types + journal document.
-- See the locked design brief (Downloads\principlesnstuff\negotiation-brief.md,
-- 2026-07-13). The runner "knows the rules so the Director doesn't have to":
-- NegotiationRules is the single source of truth for outcomes, the attitude
-- table, and the offers ladder, so the stage/rail never re-encode the numbers.
--==============================================================================

NegotiationRules = rawget(_G, "NegotiationRules") or {}

--Starting interest/patience by attitude (book table, Heroes p.286).
NegotiationRules.attitudes = {
    { id = "hostile",    name = "Hostile",    interest = 1, patience = 2 },
    { id = "suspicious", name = "Suspicious", interest = 2, patience = 2 },
    { id = "neutral",    name = "Neutral",    interest = 2, patience = 3 },
    { id = "open",       name = "Open",       interest = 3, patience = 3 },
    { id = "friendly",   name = "Friendly",   interest = 3, patience = 4 },
    { id = "trusting",   name = "Trusting",   interest = 3, patience = 5 },
}

function NegotiationRules.AttitudeById(id)
    for _, a in ipairs(NegotiationRules.attitudes) do
        if a.id == id then return a end
    end
    return NegotiationRules.attitudes[2] --default Suspicious
end

--The six disposition band labels for interest 0..5 (stage, bands mode).
--Deliberately NOT the attitude words so the prep dropdown and the live
--meter never read as the same vocabulary (brief open q.1, Lisa-signed).
NegotiationRules.bands = {
    [0] = "Done with you",
    [1] = "Unmoved",
    [2] = "Wary",
    [3] = "Listening",
    [4] = "Receptive",
    [5] = "Won over",
}

--Patience cue lines, patience 0..5 (prose, player-facing).
NegotiationRules.patienceCues = {
    [0] = "He's done listening.",
    [1] = "One weak word could end this.",
    [2] = "His patience is thinning.",
    [3] = "He's hearing you out.",
    [4] = "He's got time for you.",
    [5] = "He's in no hurry.",
}

--Offer ladder shape by interest 0..5 (book, Heroes p.288). These are the
--public "shape" of the deal; specific terms are prepped per negotiation.
NegotiationRules.offerLabels = {
    [0] = "No, and...",
    [1] = "No.",
    [2] = "No, but...",
    [3] = "Yes, but...",
    [4] = "Yes.",
    [5] = "Yes, and...",
}

NegotiationRules.MAX = 5

--Offers are stored as a 6-entry ARRAY, never a map keyed by the interest
--number. A table with numeric-LOOKING string keys ("0".."5") is serialized
--as an array and silently re-indexed 1-based on the round-trip through the
--shared doc, which shifts every offer by one. index = interest + 1.
function NegotiationRules.OfferIndex(interest)
    return interest + 1
end

local function clamp05(n)
    if n < 0 then return 0 end
    if n > NegotiationRules.MAX then return NegotiationRules.MAX end
    return n
end

--Tier from a power-roll total (standard Draw Steel boundaries).
function NegotiationRules.TierForTotal(total)
    if total <= 11 then return 1 end
    if total <= 16 then return 2 end
    return 3
end

--Resolve one argument against the rules. Returns a delta table:
--  { interest = <int>, patience = <int>, marksUsed = <bool>, note = <string> }
--interest/patience are DELTAS (may be negative); the caller clamps.
--args:
--  track   = "appeal" | "nomotivation" | "pitfall"
--  tier    = 1 | 2 | 3            (ignored for pitfall)
--  repeated= bool  (appeal: motivation already used; nomotivation: same arg again)
--  natHigh = bool  (nomotivation: natural 19-20)
--  lie     = bool  (caught in a lie: extra interest -1 when interest didn't rise)
function NegotiationRules.Resolve(args)
    local track = args.track
    local tier = args.tier or 1
    local d = { interest = 0, patience = 0, marksUsed = false, note = "" }

    if track == "pitfall" then
        --auto-fail; roll ignored.
        d.interest = -1
        d.patience = -1
        d.note = "Hit a pitfall - that touched something sore."
    elseif track == "appeal" then
        d.marksUsed = true
        if args.repeated then
            --repeating an already-appealed motivation: patience only.
            d.patience = -1
            d.note = "Already appealed to - patience only."
        elseif tier >= 3 then
            d.interest = 1
            d.note = "A strong appeal landed."
        elseif tier == 2 then
            d.interest = 1
            d.patience = -1
            d.note = "The appeal landed."
        else
            d.patience = -1
            d.note = "The appeal fell short."
        end
    else --nomotivation
        if args.repeated then
            tier = 1 --repeating the same no-motivation argument: auto tier 1.
            d.note = "Repeated argument - no traction."
        end
        if tier >= 3 then
            d.interest = 1
            d.patience = -1
            d.note = d.note ~= "" and d.note or "A well-made point."
        elseif tier == 2 then
            d.patience = -1
            d.note = d.note ~= "" and d.note or "He's unmoved but listening."
        else
            d.interest = -1
            d.patience = -1
            d.note = d.note ~= "" and d.note or "That went nowhere."
        end
        if args.natHigh then
            --natural 19-20: patience unchanged.
            d.patience = 0
        end
    end

    --caught in a lie: extra interest -1, but only when the argument did not
    --raise interest (book condition).
    if args.lie and d.interest <= 0 then
        d.interest = d.interest - 1
        d.note = d.note .. " Caught in a lie."
    end

    return d
end

--Apply a resolved delta to interest/patience numbers, clamped. Returns the
--new {interest, patience}.
function NegotiationRules.ApplyDelta(interest, patience, d)
    return clamp05(interest + (d.interest or 0)), clamp05(patience + (d.patience or 0))
end

--Is this a terminal state? Returns nil or a reason string.
function NegotiationRules.Terminal(interest, patience)
    if interest >= NegotiationRules.MAX then return "final" end   --interest 5
    if interest <= 0 then return "nodeal" end                     --interest 0
    if patience <= 0 then return "final" end                      --patience 0
    return nil
end

--------------------------------------------------------------------------------
-- LiveNegotiation: the in-play state, carried in the shared presentdialog
-- doc's livedata (mirrors LiveMontage). Everything the stage + rail read.
--------------------------------------------------------------------------------
LiveNegotiation = RegisterGameType("LiveNegotiation")
LiveNegotiation.docid = ""          --the backing NegotiationDocument id.
LiveNegotiation.npcName = ""
LiveNegotiation.npcDesc = ""
LiveNegotiation.portrait = ""
LiveNegotiation.nameRevealed = true
--Director-only provenance, shown in the rail, never on the stage: the sample
--negotiator this run is playing, and how hard he is to move (impression 1-12).
LiveNegotiation.archetype = ""
LiveNegotiation.impression = 1
LiveNegotiation.interest = 2
LiveNegotiation.patience = 3
LiveNegotiation.showRaw = false     --bands (false) vs raw numbers (true) on stage.
LiveNegotiation.floor = ""          --charid currently composing, or "".
LiveNegotiation.floorAt = 0         --server ms the floor was claimed.
LiveNegotiation.offerRevealed = false
LiveNegotiation.ended = false
--traits: array of { id, kind ("motivation"|"pitfall"), name, line, revealed, used }
LiveNegotiation.traits = {}
--offers: map interest(string) -> { terms=string, revealed=bool }
LiveNegotiation.offers = {}
--accepted: map charid -> "accepted" | "declined"
LiveNegotiation.accepted = {}
--spoke: map charid -> number of arguments that hero has made. Draw Steel puts
--NO turn order on a negotiation - any hero may argue at any time - so the way
--to keep one player from carrying the whole scene is to make participation
--VISIBLE, not to gate it. A tally nudges; a rule would be one we invented.
LiveNegotiation.spoke = {}
--history: the STORY BEATS the table sees - arguments and their outcomes,
--NPC lines, offers, accepts. array of { who, text, cue, tone }
--tone: good | bad | neutral | npc | system
LiveNegotiation.history = {}
--audit: DIRECTOR-ONLY bookkeeping - floor churn, the numbers toggle, manual
--meter corrections. Never rendered on the stage: a fat-finger meter fix must
--not read to the table as an NPC mood swing. array of { text }
LiveNegotiation.audit = {}
--pending: false, or the argument awaiting the Director's Resolve:
--  { who, whoName, roll, natHigh, angleTraitId }
--(false, never nil: a nil default does not register the field, and reads of
--an unregistered field on a game type RAISE.)
LiveNegotiation.pending = false
--pendingReveal: false, or a tier-3 discovery awaiting the Director's pick:
--  { who, whoName, kind }
LiveNegotiation.pendingReveal = false

function LiveNegotiation.FromDocument(doc)
    local att = NegotiationRules.AttitudeById(doc:try_get("attitude", "suspicious"))
    local live = LiveNegotiation.new{
        docid = doc.id,
        npcName = doc:try_get("npcName", "") ~= "" and doc.npcName or doc.description,
        npcDesc = doc:try_get("npcDesc", ""),
        portrait = doc:try_get("portrait", ""),
        nameRevealed = not doc:try_get("hideName", false),
        archetype = doc:try_get("archetype", ""),
        impression = doc:try_get("impression", 1),
        interest = doc:try_get("startInterest", att.interest),
        patience = doc:try_get("startPatience", att.patience),
        traits = {},
        offers = {},
        accepted = {},
        history = {},
        spoke = {},
    }
    for _, t in ipairs(doc:try_get("traits", {})) do
        live.traits[#live.traits + 1] = {
            id = t.id or dmhub.GenerateGuid(),
            kind = t.kind or "motivation",
            name = t.name or "",
            line = t.line or "",
            revealed = false,
            used = false,
        }
    end
    local docOffers = doc:try_get("offers", {})
    for i = 0, NegotiationRules.MAX do
        local idx = NegotiationRules.OfferIndex(i)
        local o = docOffers[idx]
        live.offers[idx] = { terms = (o and o.terms) or "", revealed = false }
    end
    return live
end

--------------------------------------------------------------------------------
-- NegotiationDocument: the journal prep doc + record. Registers as a real
-- journal document type (unlike montage, whose registration is commented
-- out). The read view is a scene page; "Begin Negotiation" presents the stage.
--------------------------------------------------------------------------------
NegotiationDocument = RegisterGameType("NegotiationDocument", "CustomDocument")
NegotiationDocument.nodeType = "negotiation"
NegotiationDocument.npcName = ""
NegotiationDocument.npcDesc = ""
NegotiationDocument.portrait = ""
NegotiationDocument.hideName = false
NegotiationDocument.attitude = "suspicious"
NegotiationDocument.startInterest = -1   --<0 means "derive from attitude"
NegotiationDocument.startPatience = -1
NegotiationDocument.impression = 1
--The Sample Negotiator this was seeded from, by name. The seed is a COPY (the
--Director edits the traits freely afterwards), so this is a provenance label,
--not a live link - but without it the run forgets what it is playing, and the
--rail can only say who the NPC is, never what kind of negotiator he is.
NegotiationDocument.archetype = ""
NegotiationDocument.opening = ""
NegotiationDocument.stakes = ""
--traits: array of { id, kind, name, line }
NegotiationDocument.traits = {}
--offers: map interest(string) -> { terms }
NegotiationDocument.offers = {}
--summaries: array of appended run records (strings).
NegotiationDocument.summaries = {}

function NegotiationDocument.CreateNew(args)
    local doc = NegotiationDocument.new{
        description = "New Negotiation",
        npcName = "",
        npcDesc = "",
        attitude = "suspicious",
        impression = 1,
        traits = {},
        offers = {},
        summaries = {},
    }
    if args then
        for k, v in pairs(args) do doc[k] = v end
    end
    return doc
end

--Seed traits + impression from a compendium Negotiator archetype, copying
--the voiced lines so the prep doc carries performance material.
function NegotiationDocument:SeedFromArchetype(negotiator)
    self.archetype = negotiator.name or ""
    self.impression = negotiator:try_get("impressionScore", 1)
    if self.description == "New Negotiation" or self.description == "" then
        self.npcDesc = negotiator:try_get("flavorText", "")
    end
    local traits = {}
    for _, m in ipairs(negotiator:try_get("motivations", {})) do
        traits[#traits + 1] = { id = dmhub.GenerateGuid(), kind = "motivation",
            name = m.name or "", line = m.description or "" }
    end
    for _, p in ipairs(negotiator:try_get("pitfalls", {})) do
        traits[#traits + 1] = { id = dmhub.GenerateGuid(), kind = "pitfall",
            name = p.name or "", line = p.description or "" }
    end
    self.traits = traits
end

--Resolve the starting interest/patience (explicit override or attitude table).
function NegotiationDocument:StartingMeters()
    local att = NegotiationRules.AttitudeById(self.attitude)
    local i = self:try_get("startInterest", -1)
    local p = self:try_get("startPatience", -1)
    return (i and i >= 0) and i or att.interest, (p and p >= 0) and p or att.patience
end

--==============================================================================
-- NegotiationRun: the live controller. All live state lives in the shared
-- presentdialog doc's livedata, so the stage and the rail read the same
-- object on every client (the montage pattern). Nothing here touches token
-- properties.
--==============================================================================

NegotiationRun = rawget(_G, "NegotiationRun") or {}

local DIALOG_ID = "negotiation"

function NegotiationRun.Doc()
    return GameHud.GetPresentDialogDoc(DIALOG_ID)
end

--The live negotiation, or nil when nothing is running.
function NegotiationRun.Live()
    local doc = NegotiationRun.Doc()
    if doc == nil then
        return nil
    end
    local live = doc.data.livedata
    if live == nil or live:try_get("ended", false) then
        return live
    end
    return live
end

--Mutate live state inside a shared-doc change. fn(live) does the work.
function NegotiationRun.Mutate(desc, fn)
    local doc = NegotiationRun.Doc()
    if doc == nil then
        return
    end
    local live = doc.data.livedata
    if live == nil then
        return
    end
    doc:BeginChange()
    fn(live)
    doc:CompleteChange(desc or "Negotiation")
end

--Append a STORY BEAT (the table sees this). tone: good|bad|neutral|npc|system.
function NegotiationRun.Log(live, who, text, cue, tone)
    local h = live.history
    h[#h + 1] = {
        who = who or "",
        text = text or "",
        cue = cue or "",
        tone = tone or "neutral",
    }
end

--Append a Director-only audit line (bookkeeping; never on the stage).
function NegotiationRun.Audit(live, text)
    local a = live:get_or_add("audit", {})
    a[#a + 1] = { text = text or "" }
end

function NegotiationRun.TraitById(live, id)
    for _, t in ipairs(live.traits) do
        if t.id == id then
            return t
        end
    end
    return nil
end

--Begin a negotiation from a prep document: build the live state and present
--the stage to every client.
function NegotiationRun.Begin(negotiationDoc, hostPanel)
    local live = LiveNegotiation.FromDocument(negotiationDoc)
    NegotiationRun.Log(live, "", "", string.format("The negotiation with %s begins.",
        live.npcName ~= "" and live.npcName or "the NPC"), "system")
    GameHud.PresentDialogToUsers(hostPanel, DIALOG_ID, { docid = negotiationDoc.id }, live)
end

--Resolve the pending argument with the Director's classification.
--opts: track, tier, traitId (appeal/pitfall target), lie
function NegotiationRun.ResolvePending(opts)
    NegotiationRun.Mutate("Resolve argument", function(live)
        local pending = live:try_get("pending", false)
        if not pending then
            return
        end

        local trait = opts.traitId ~= nil and NegotiationRun.TraitById(live, opts.traitId) or nil
        local repeated = false
        if opts.track == "appeal" and trait ~= nil then
            --the motivation-once rule: the engine knows this one by itself.
            repeated = trait.used == true
        elseif opts.track == "nomotivation" then
            --the same-argument-twice rule: only the Director can judge whether
            --this is a line the heroes have already tried, so they tell us.
            repeated = opts.repeated == true
        end

        local d = NegotiationRules.Resolve{
            track = opts.track,
            tier = opts.tier,
            repeated = repeated,
            natHigh = pending.natHigh,
            lie = opts.lie,
        }

        local i, p = NegotiationRules.ApplyDelta(live.interest, live.patience, d)
        live.interest = i
        live.patience = p

        --an appeal that lands on a hidden motivation reveals it: the player
        --found it. (Pitfalls reveal too -- they learned it the hard way.)
        local cue = d.note
        if trait ~= nil then
            if opts.track == "appeal" then
                trait.used = true
                if not trait.revealed then
                    trait.revealed = true
                    cue = string.format("You found something %s cares about - %s.",
                        live.npcName ~= "" and live.npcName or "he", trait.name)
                end
            elseif opts.track == "pitfall" and not trait.revealed then
                trait.revealed = true
                cue = string.format("That touched something sore - %s. No argument could have landed there.",
                    trait.name)
            end
        end

        local tone = "neutral"
        if d.interest > 0 then
            tone = "good"
        elseif d.interest < 0 or (opts.track == "pitfall") then
            tone = "bad"
        end

        --a resolved argument counts toward who has carried the scene. Dismissed
        --ones do not: they never happened.
        local who = pending.who or ""
        if who ~= "" then
            local spoke = live:get_or_add("spoke", {})
            spoke[who] = (spoke[who] or 0) + 1
        end

        NegotiationRun.Log(live, pending.whoName or "", pending.text or "", cue, tone)
        live.pending = false
        live.floor = ""
    end)
end

--Dismiss the pending argument: no meters, no history, floor cleared.
function NegotiationRun.DismissPending()
    NegotiationRun.Mutate("Dismiss argument", function(live)
        live.pending = false
        live.floor = ""
    end)
end

--Reveal / hide a trait on the stage.
function NegotiationRun.SetTraitRevealed(traitId, revealed)
    NegotiationRun.Mutate("Reveal trait", function(live)
        local t = NegotiationRun.TraitById(live, traitId)
        if t == nil then
            return
        end
        t.revealed = revealed
        if revealed then
            NegotiationRun.Log(live, "", "", string.format("Something about %s has become clear.",
                live.npcName ~= "" and live.npcName or "the NPC"), "system")
        end
    end)
end

--Adjust a meter by hand (Director correction). Logged Director-only (the
--audit strip reads these), never as an NPC mood line on the stage.
function NegotiationRun.AdjustMeter(which, delta)
    NegotiationRun.Mutate("Adjust " .. which, function(live)
        if which == "interest" then
            live.interest = math.max(0, math.min(NegotiationRules.MAX, live.interest + delta))
        else
            live.patience = math.max(0, math.min(NegotiationRules.MAX, live.patience + delta))
        end
        NegotiationRun.Audit(live, string.format("%s %s%d (manual)",
            which == "interest" and "Interest" or "Patience",
            delta > 0 and "+" or "", delta))
    end)
end

--The coach line: what the rules expect right now. Director-facing.
function NegotiationRun.CoachLine(live)
    local npc = live.npcName ~= "" and live.npcName or "the NPC"
    if live:try_get("pendingReveal", false) then
        local pr = live.pendingReveal
        return string.format("Waiting on %s's discovery pick.", pr.whoName or "the hero")
    end
    if live:try_get("pending", false) then
        return "Classify the argument, then Resolve - the rules apply themselves."
    end
    local terminal = NegotiationRules.Terminal(live.interest, live.patience)
    if terminal == "nodeal" then
        return string.format("Interest is 0 - %s offers nothing and ends it. No deal.", npc)
    elseif terminal == "final" then
        return string.format("This is %s's FINAL offer - reveal the terms and let them answer.", npc)
    end
    if #live.history <= 1 then
        return string.format("%s speaks first - the heroes must choose to negotiate.", npc)
    end
    if live.patience <= 1 then
        return string.format("Patience is %d. One weak argument ends this.", live.patience)
    end
    return string.format("Respond as %s, then make his offer - at Interest %d that's a \"%s\"",
        npc, live.interest, NegotiationRules.offerLabels[live.interest] or "")
end

--==============================================================================
-- The prep document's faces: an authoring form (EditPanel) and a scene page
-- (DisplayPanel) the Director reads before the scene. Registered as a real
-- journal document type.
--==============================================================================

local LOOP_REFERENCE = [[**The loop.** One hero argues; you classify what they said and Resolve - the runner applies the rules.
- **Appeals to a motivation** (each usable once): tier 1 costs patience; tier 2 raises interest and costs patience; tier 3 raises interest only.
- **No motivation:** tier 1 loses interest and patience; tier 2 costs patience; tier 3 raises interest and costs patience. A natural 19-20 costs no patience.
- **Hits a pitfall:** automatic failure - interest and patience both drop, whatever they rolled.
- **Read them** (a test): tier 3 reveals a motivation or pitfall; tier 1 costs patience.
- **After every argument**, respond as the NPC and state his offer for the current interest.
- **It ends** at interest 5 or patience 0 (final offer), at interest 0 (no deal), or when the heroes take the deal on the table.]]

local function SectionHeader(text)
    return gui.Label{
        classes = { "bold", "sizeM" },
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 6,
        text = text,
    }
end

function NegotiationDocument:EditPanel()
    local doc = self

    --provenance: which Sample Negotiator this was seeded from. The seed is a
    --copy, so this is a label, not a link - but it is the only thing that tells
    --the Director (and later the rail) what kind of negotiator he is running.
    local seedNote
    local function SeedNoteText()
        local a = doc:try_get("archetype", "")
        if a == "" then
            return ""
        end
        return string.format("Seeded from %s (impression %d). The traits are yours to edit - this is a copy.",
            a, doc:try_get("impression", 1))
    end
    seedNote = gui.Label{
        classes = { "sizeS" },
        width = "94%", height = "auto", halign = "left", vmargin = 3,
        fontSize = 12, color = "#7a7468", textWrap = true,
        text = SeedNoteText(),
    }

    local function textInput(field, placeholder, multiline)
        return gui.Input{
            classes = { "sizeM" },
            width = "94%",
            height = multiline and 60 or 26,
            halign = "left",
            multiline = multiline,
            placeholderText = placeholder,
            text = doc:try_get(field, ""),
            change = function(element)
                doc[field] = element.text
                doc:Upload()
            end,
        }
    end

    --Traits (motivations + pitfalls) with their voiced lines.
    local traitsPanel
    local function RebuildTraits()
        local children = {}
        for _, kind in ipairs({ "motivation", "pitfall" }) do
            children[#children + 1] = gui.Label{
                classes = { "bold" },
                width = "auto", height = "auto", halign = "left", vmargin = 4,
                text = kind == "motivation" and "What they want (motivations)" or "Never touch (pitfalls)",
            }
            for _, t in ipairs(doc:try_get("traits", {})) do
                if t.kind == kind then
                    local trait = t
                    children[#children + 1] = gui.Panel{
                        flow = "horizontal", width = "94%", height = "auto",
                        halign = "left", vmargin = 2,
                        gui.Input{
                            classes = { "sizeS" }, width = 160, height = 24, valign = "top",
                            placeholderText = "Name", text = trait.name,
                            change = function(element)
                                trait.name = element.text
                                doc:Upload()
                            end,
                        },
                        gui.Input{
                            classes = { "sizeS" }, width = 420, height = "auto",
                            valign = "top", multiline = true, lmargin = 6,
                            placeholderText = "What they say about it (their voice)",
                            text = trait.line,
                            change = function(element)
                                trait.line = element.text
                                doc:Upload()
                            end,
                        },
                        gui.Button{
                            classes = { "sizeS" }, width = 70, height = 24, lmargin = 6,
                            text = "Remove",
                            click = function()
                                local list = doc.traits
                                for i, x in ipairs(list) do
                                    if x.id == trait.id then
                                        table.remove(list, i)
                                        break
                                    end
                                end
                                doc:Upload()
                                RebuildTraits()
                            end,
                        },
                    }
                end
            end
            children[#children + 1] = gui.Button{
                classes = { "sizeS" }, width = 160, height = 24, halign = "left", vmargin = 3,
                text = kind == "motivation" and "+ Add Motivation" or "+ Add Pitfall",
                click = function()
                    local list = doc:get_or_add("traits", {})
                    list[#list + 1] = { id = dmhub.GenerateGuid(), kind = kind, name = "", line = "" }
                    doc:Upload()
                    RebuildTraits()
                end,
            }
        end
        traitsPanel.children = children
    end

    traitsPanel = gui.Panel{
        flow = "vertical", width = "100%", height = "auto", halign = "left",
        create = function() RebuildTraits() end,
    }

    --Offers ladder 0..5.
    local offerRows = {}
    for i = NegotiationRules.MAX, 0, -1 do
        local interest = i
        offerRows[#offerRows + 1] = gui.Panel{
            flow = "horizontal", width = "94%", height = "auto", halign = "left", vmargin = 2,
            gui.Label{
                width = 150, height = 24, valign = "center",
                text = string.format("%d  \"%s\"", interest, NegotiationRules.offerLabels[interest]),
            },
            gui.Input{
                classes = { "sizeS" }, width = 460, height = "auto", multiline = true,
                placeholderText = "What he offers (leave blank to use the book's line)",
                text = (doc:try_get("offers", {})[NegotiationRules.OfferIndex(interest)] or {}).terms or "",
                change = function(element)
                    local offers = doc:get_or_add("offers", {})
                    --the array must stay contiguous or it serializes badly.
                    for i = 0, NegotiationRules.MAX do
                        local idx = NegotiationRules.OfferIndex(i)
                        offers[idx] = offers[idx] or { terms = "" }
                    end
                    offers[NegotiationRules.OfferIndex(interest)] = { terms = element.text }
                    doc:Upload()
                end,
            },
        }
    end

    local attitudeOptions = {}
    for _, a in ipairs(NegotiationRules.attitudes) do
        attitudeOptions[#attitudeOptions + 1] = {
            id = a.id,
            text = string.format("%s  (Interest %d, Patience %d)", a.name, a.interest, a.patience),
        }
    end

    return gui.Panel{
        width = "100%", height = "100%", flow = "vertical", vscroll = true,

        SectionHeader("The NPC"),
        gui.Panel{
            flow = "horizontal", width = "94%", height = "auto", halign = "left",
            --portrait: the face the table sees on the stage.
            gui.IconEditor{
                library = "Avatar",
                width = 96, height = 120,
                valign = "top", rmargin = 12,
                bgcolor = "white",
                allowNone = true,
                value = doc:try_get("portrait", ""),
                change = function(element)
                    doc.portrait = element.value or ""
                    doc:Upload()
                end,
            },
            gui.Panel{
                flow = "vertical", width = "100%-108", height = "auto",
                gui.Input{
                    classes = { "sizeL" }, width = "100%", height = 30, halign = "left",
                    placeholderText = "Negotiation title (e.g. Reeve Halric)",
                    text = doc.description,
                    change = function(element)
                        doc.description = element.text
                        doc:Upload()
                    end,
                },
                textInput("npcName", "NPC name (as the players hear it)"),
                textInput("npcDesc", "Who they are, in a line (e.g. Town reeve - holds the gate keys)"),
                gui.Check{
                    classes = { "sizeS" },
                    width = "100%", height = 24, minWidth = 0,
                    text = "Start unnamed (\"???\" until revealed)",
                    value = doc:try_get("hideName", false),
                    change = function(element)
                        doc.hideName = element.value
                        doc:Upload()
                    end,
                },
            },
        },

        SectionHeader("Seed from an archetype"),
        gui.Button{
            classes = { "sizeM" }, width = 260, height = 26, halign = "left",
            text = "Seed from a Sample Negotiator...",
            click = function(element)
                local entries = {}
                local list = {}
                for id, neg in unhidden_pairs(dmhub.GetTable(Negotiator.tableName) or {}) do
                    list[#list + 1] = neg
                end
                table.sort(list, function(a, b)
                    return (a:try_get("impressionScore", 1)) < (b:try_get("impressionScore", 1))
                end)
                for _, neg in ipairs(list) do
                    local negotiator = neg
                    entries[#entries + 1] = {
                        text = string.format("%d  %s", negotiator:try_get("impressionScore", 1), negotiator.name),
                        click = function()
                            element.popup = nil
                            doc:SeedFromArchetype(negotiator)
                            doc:Upload()
                            seedNote.text = SeedNoteText()
                            RebuildTraits()
                        end,
                    }
                end
                element.popup = gui.ContextMenu{ entries = entries }
            end,
        },
        seedNote,

        SectionHeader("Starting attitude"),
        gui.Dropdown{
            classes = { "sizeM" }, width = 300, height = 30, halign = "left",
            options = attitudeOptions,
            idChosen = doc:try_get("attitude", "suspicious"),
            change = function(element)
                doc.attitude = element.idChosen
                doc:Upload()
            end,
        },

        SectionHeader("The opening"),
        textInput("opening", "How they enter, and their first line. The NPC speaks first.", true),

        SectionHeader("Motivations & Pitfalls"),
        traitsPanel,

        SectionHeader("What they offer, by interest"),
        gui.Panel{
            flow = "vertical", width = "100%", height = "auto", halign = "left",
            children = offerRows,
        },

        SectionHeader("Stakes"),
        textInput("stakes", "What happens on a deal - and on no deal.", true),
    }
end

function NegotiationDocument:DisplayPanel()
    local doc = self
    local resultPanel

    local interest, patience = doc:StartingMeters()
    local att = NegotiationRules.AttitudeById(doc:try_get("attitude", "suspicious"))

    local function md(text, classes)
        return gui.Label{
            classes = classes or { "sizeS" },
            width = "95%", height = "auto", halign = "left",
            markdown = true, textWrap = true, textAlignment = "topleft",
            vmargin = 2,
            text = text,
        }
    end

    --want / never-touch, with the voiced lines.
    local function TraitGroup(kind, heading)
        local rows = {}
        for _, t in ipairs(doc:try_get("traits", {})) do
            if t.kind == kind and (t.name or "") ~= "" then
                local line = (t.line or "")
                rows[#rows + 1] = md(string.format("**%s** %s", t.name,
                    line ~= "" and ("\n\n> " .. line) or ""))
            end
        end
        if #rows == 0 then
            return nil
        end
        local children = { SectionHeader(heading) }
        for _, r in ipairs(rows) do
            children[#children + 1] = r
        end
        return gui.Panel{
            flow = "vertical", width = "100%", height = "auto", halign = "left",
            children = children,
        }
    end

    local offerRows = {}
    for i = NegotiationRules.MAX, 0, -1 do
        local o = (doc:try_get("offers", {})[NegotiationRules.OfferIndex(i)] or {})
        local terms = (o.terms or "")
        offerRows[#offerRows + 1] = md(string.format("**%d - \"%s\"**  %s", i,
            NegotiationRules.offerLabels[i],
            terms ~= "" and terms or "*(the book's line)*"))
    end

    local summaryChildren = {}
    for _, s in ipairs(doc:try_get("summaries", {})) do
        summaryChildren[#summaryChildren + 1] = md(s)
    end

    local body = gui.Panel{
        width = "100%", height = "100%-50", flow = "vertical", valign = "top", vscroll = true,

        gui.Label{
            classes = { "bold", "sizeXl" },
            width = "auto", height = "auto", halign = "left", vmargin = 4,
            text = doc.description,
        },
        md(string.format("%s%s",
            doc:try_get("npcDesc", "") ~= "" and (doc.npcDesc .. "\n\n") or "",
            string.format("**%s** - starts at **Interest %d**, **Patience %d**.  Impression **%d**.",
                att.name, interest, patience, doc:try_get("impression", 1)))),

        TraitGroup("motivation", "What they want"),
        TraitGroup("pitfall", "Never touch"),

        (doc:try_get("opening", "") ~= "") and gui.Panel{
            flow = "vertical", width = "100%", height = "auto",
            SectionHeader("The opening"),
            md(doc.opening),
        } or nil,

        SectionHeader("What they offer"),
        gui.Panel{
            flow = "vertical", width = "100%", height = "auto", halign = "left",
            children = offerRows,
        },

        (doc:try_get("stakes", "") ~= "") and gui.Panel{
            flow = "vertical", width = "100%", height = "auto",
            SectionHeader("Stakes"),
            md(doc.stakes),
        } or nil,

        SectionHeader("How negotiation works"),
        md(LOOP_REFERENCE),

        (#summaryChildren > 0) and gui.Panel{
            flow = "vertical", width = "100%", height = "auto",
            children = (function()
                local c = { SectionHeader("Past runs") }
                for _, s in ipairs(summaryChildren) do c[#c + 1] = s end
                return c
            end)(),
        } or nil,
    }

    resultPanel = gui.Panel{
        width = "100%", height = "100%", flow = "vertical",
        body,
        dmhub.isDM and gui.Button{
            classes = { "bold", "sizeXl" },
            valign = "bottom", halign = "center",
            text = "Begin Negotiation",
            click = function(element)
                NegotiationRun.Begin(doc, resultPanel)
                local framed = element:FindParentWithClass("framedPanel")
                if framed ~= nil then
                    framed:DestroySelf()
                end
            end,
        } or nil,
    }

    return resultPanel
end

CustomDocument.Register{
    id = "negotiation",
    text = "New Negotiation",
    create = function()
        return NegotiationDocument.CreateNew{}
    end,
}

--==============================================================================
-- THE CENTER STAGE -- one shared dialog, presented to every client. Players
-- read the room and make their case here; the Director watches the same
-- surface the table sees.
--==============================================================================

local ARGUMENT_ATTRS = { "rea", "inu", "prs" } --Reason / Intuition / Presence.

local function CreateNegotiationStage(args)
    local isDM = dmhub.isDM
    local doc = NegotiationRun.Doc()
    if doc == nil then
        return nil
    end

    local m_live = doc.data.livedata
    if m_live == nil then
        return nil
    end

    --composer state (local to this client).
    local m_angle = nil     --trait id, or nil for "a new angle".
    local m_attr = "prs"

    local function MyCharId()
        local tok = dmhub.currentToken
        return tok ~= nil and tok.charid or nil
    end

    local function IHaveFloor(live)
        local me = MyCharId()
        return me ~= nil and live.floor == me
    end

    ----------------------------------------------------------------------
    -- Left column: reading the NPC.
    ----------------------------------------------------------------------
    --Identity: portrait + name + descriptor. An unrevealed NPC shows an empty
    --frame and "???" (the reveal grammar covers identity too).
    local portraitPanel = gui.Panel{
        classes = { "image" },
        width = 96, height = 120,
        valign = "top", rmargin = 14,
        bgcolor = "white",
        borderWidth = 1,
        borderColor = "#ffffff47",
        refreshNeg = function(element, live)
            local p = live:try_get("portrait", "")
            local show = live.nameRevealed and p ~= ""
            element.selfStyle.bgimage = show and p or nil
            element.selfStyle.bgcolor = show and "white" or "#131315"
        end,
    }

    local nameLabel = gui.Label{
        classes = { "bold", "sizeXl" },
        width = "100%", height = "auto", halign = "left",
        refreshNeg = function(element, live)
            local shown = live.nameRevealed and live.npcName ~= "" and live.npcName or "???"
            element.text = shown
        end,
    }

    local descLabel = gui.Label{
        classes = { "sizeS" },
        width = "100%", height = "auto", halign = "left",
        textWrap = true,
        color = "#8a8a8a",
        refreshNeg = function(element, live)
            element.text = live.nameRevealed and live.npcDesc or ""
        end,
    }

    local identityPanel = gui.Panel{
        flow = "horizontal", width = "100%", height = "auto", vmargin = 4,
        portraitPanel,
        gui.Panel{
            flow = "vertical", width = "100%-110", height = "auto", valign = "top",
            nameLabel,
            descLabel,
        },
    }

    --disposition bands (or raw pips when the Director reveals the numbers).
    local bandsPanel = gui.Panel{
        flow = "horizontal", width = "100%", height = "auto", vmargin = 6,
        refreshNeg = function(element, live)
            local children = {}
            if live.showRaw then
                children[#children + 1] = gui.Label{
                    classes = { "bold" }, width = "auto", height = "auto", valign = "center",
                    text = string.format("Interest %d / 5      Patience %d / 5",
                        live.interest, live.patience),
                }
            else
                for i = 0, NegotiationRules.MAX do
                    local on = (i == live.interest)
                    children[#children + 1] = gui.Label{
                        classes = { on and "bold" or "noBold" },
                        width = 64, height = 40, vpad = 4, hpad = 2, rmargin = 2,
                        borderBox = true,
                        textAlignment = "center",
                        textWrap = true,
                        fontSize = 10,
                        color = on and "#f2ede1" or "#7a7468",
                        bgimage = "panels/square.png",
                        bgcolor = on and "#ffffff14" or "#00000000",
                        border = on and 1 or 0,
                        borderColor = "#ffffff47",
                        text = NegotiationRules.bands[i],
                    }
                end
            end
            element.children = children
        end,
    }

    local patienceCue = gui.Label{
        classes = { "sizeS" },
        width = "100%", height = "auto", halign = "left", vmargin = 2,
        refreshNeg = function(element, live)
            if live.showRaw then
                element.text = ""
                return
            end
            element.text = NegotiationRules.patienceCues[live.patience] or ""
            element.selfStyle.color = (live.patience <= 2) and "#e8a030" or "#8a8a8a"
        end,
    }

    --Patience IS the argument budget - roughly one argument a point. The mood
    --cue above says how he feels; this says how much runway is left, which is
    --what the table needs to decide between pushing and taking the deal.
    local patienceBudget = gui.Label{
        classes = { "sizeS" },
        width = "100%", height = "auto", halign = "left", vmargin = 2,
        fontSize = 12,
        color = "#7a7468",
        refreshNeg = function(element, live)
            if NegotiationRules.Terminal(live.interest, live.patience) ~= nil then
                element.text = ""
                return
            end
            if live.patience <= 0 then
                element.text = ""
            elseif live.patience == 1 then
                element.text = "He'll hear one more argument, and that's the last of it."
            else
                element.text = string.format("He'll hear about %d more arguments.", live.patience)
            end
        end,
    }

    --what you've learned: two headed groups + one "more to learn" affordance.
    local learnedPanel = gui.Panel{
        flow = "vertical", width = "100%", height = "auto", vmargin = 8,
        refreshNeg = function(element, live)
            local children = {}
            local function group(kind, heading, glyph)
                local rows = {}
                for _, t in ipairs(live.traits) do
                    if t.kind == kind and t.revealed then
                        --a motivation that has already landed is SPENT: appeal to
                        --it again and the rules give you nothing but a patience
                        --cost. Say so, or the table wastes its best remaining card.
                        local spent = (kind == "motivation") and t.used == true
                        rows[#rows + 1] = gui.Label{
                            classes = { "sizeS" },
                            width = "100%", height = "auto", halign = "left", vmargin = 1,
                            textWrap = true,
                            color = spent and "#7a7468" or "#e4ddd0",
                            text = spent
                                and string.format("%s  %s - already moved him", glyph, t.name)
                                or string.format("%s  %s", glyph, t.name),
                        }
                    end
                end
                if #rows == 0 then
                    return
                end
                children[#children + 1] = gui.Label{
                    classes = { "bold" },
                    width = "100%", height = "auto", halign = "left", vmargin = 3,
                    fontSize = 12,
                    color = "#7a7468",
                    text = heading,
                }
                for _, r in ipairs(rows) do
                    children[#children + 1] = r
                end
            end
            group("motivation", "APPEAL TO THESE", "+")
            group("pitfall", "AVOID THESE", "x")

            local hidden = false
            for _, t in ipairs(live.traits) do
                if not t.revealed then
                    hidden = true
                    break
                end
            end
            if hidden then
                children[#children + 1] = gui.Label{
                    classes = { "sizeS" },
                    width = "100%", height = "auto", halign = "left", vmargin = 4,
                    color = "#7a7468",
                    text = "?  There's more to learn - keep talking.",
                }
            end
            element.children = children
        end,
    }

    ----------------------------------------------------------------------
    -- Right column: the composer + the conversation.
    ----------------------------------------------------------------------
    local composerStatus = gui.Label{
        classes = { "sizeS" },
        width = "100%", height = "auto", halign = "left", vmargin = 4,
        refreshNeg = function(element, live)
            local terminal = NegotiationRules.Terminal(live.interest, live.patience)
            if terminal ~= nil then
                element.text = "The talking is done."
            elseif live:try_get("pending", false) then
                local p = live.pending
                element.text = string.format("%s made their case - %s is weighing it...",
                    p.whoName or "A hero",
                    live.nameRevealed and live.npcName ~= "" and live.npcName or "the NPC")
            elseif live.floor ~= "" and not IHaveFloor(live) then
                local tok = dmhub.GetCharacterById(live.floor)
                element.text = string.format("%s is making their case...",
                    tok ~= nil and tok.name or "Another hero")
            else
                element.text = "The floor is open - make your case."
            end
        end,
    }

    local anglePanel = gui.Panel{
        flow = "horizontal", width = "100%", height = "auto", wrap = true, vmargin = 4,
        refreshNeg = function(element, live)
            local children = {}
            local function chip(id, text)
                local selected = (m_angle == id)
                children[#children + 1] = gui.Label{
                    classes = { "sizeS", "hoverable" },
                    width = "auto", height = "auto",
                    hpad = 10, vpad = 5, margin = 3,
                    borderBox = true,
                    bgimage = "panels/square.png",
                    bgcolor = selected and "#ffffff1f" or "#00000000",
                    border = 1,
                    borderColor = selected and "#ffffff99" or "#ffffff47",
                    text = text,
                    press = function()
                        m_angle = id
                        element:FireEventOnParents("refreshNegLocal")
                    end,
                }
            end
            for _, t in ipairs(live.traits) do
                if t.kind == "motivation" and t.revealed and not t.used then
                    chip(t.id, t.name)
                end
            end
            chip(nil, "Try a new angle")
            element.children = children
        end,
    }

    --The second sentence is the player-facing half of the Director's repeated-
    --argument checkbox: a line he has already heard lands on tier 1 by rule.
    local angleHelp = gui.Label{
        classes = { "sizeS" },
        width = "100%", height = "auto", halign = "left", textWrap = true,
        color = "#7a7468", fontSize = 11,
        text = "A new angle may strike a motivation you haven't uncovered. Making an argument he has already heard won't land - find a new one.",
    }

    local sayInput = gui.Input{
        classes = { "sizeS" },
        width = "100%", height = 54, multiline = true, vmargin = 8,
        hpad = 8, vpad = 6, borderBox = true,
        textAlignment = "topleft",
        bgimage = "panels/square.png",
        bgcolor = "#0a0a0b",
        border = 1,
        borderColor = "#ffffff47",
        placeholderText = "What you say (optional)",
        text = "",
    }

    local attrPanel = gui.Panel{
        flow = "horizontal", width = "100%", height = "auto", vmargin = 4,
        refreshNeg = function(element)
            local children = {}
            local tok = dmhub.currentToken
            for _, attrid in ipairs(ARGUMENT_ATTRS) do
                local a = attrid
                local info = creature.attributesInfo[a]
                local selected = (m_attr == a)
                local label = info ~= nil and info.description or a

                --Which characteristic to roll is THE choice in the composer, and
                --a player should not have to open their sheet to make it. Put
                --their own modifier on their own button.
                if tok ~= nil then
                    local mod = nil
                    pcall(function()
                        mod = tok.properties:GetAttribute(a):Modifier()
                    end)
                    if mod ~= nil then
                        label = string.format("%s  %s%d", label, mod >= 0 and "+" or "", mod)
                    end
                end

                children[#children + 1] = gui.Label{
                    classes = { "sizeS", "hoverable" },
                    width = 164, height = "auto", vpad = 7, rmargin = 6,
                    textAlignment = "center", borderBox = true,
                    bgimage = "panels/square.png",
                    bgcolor = selected and "#ffffff1f" or "#00000000",
                    border = 1,
                    borderColor = selected and "#ffffff99" or "#ffffff47",
                    text = label,
                    press = function()
                        m_attr = a
                        element:FireEventOnParents("refreshNegLocal")
                    end,
                }
            end
            element.children = children
        end,
    }

    --Roll an argument or a discovery test through the real dice system.
    local function MakeRoll(kind)
        local tok = dmhub.currentToken
        if tok == nil then
            return
        end
        local live = doc.data.livedata
        if live == nil then
            return
        end

        local modifier = 0
        pcall(function()
            modifier = tok.properties:GetAttribute(m_attr):Modifier()
        end)
        local rollStr = string.format("2d10%s%d", modifier >= 0 and "+" or "", modifier)

        --claim the floor (confirm-after-sync: the doc is the truth). Floor
        --churn is bookkeeping - it goes to the Director's audit, not the stage
        --(the composer already shows who holds the floor, live).
        NegotiationRun.Mutate("Claim floor", function(l)
            l.floor = tok.charid
            l.floorAt = dmhub.serverTimeMilliseconds
            NegotiationRun.Audit(l, string.format("floor: %s", tok.name))
        end)

        local text = sayInput.text or ""
        local angleId = m_angle

        dmhub.Roll{
            guid = dmhub.GenerateGuid(),
            roll = rollStr,
            description = kind == "read" and "Read the NPC" or "Negotiation argument",
            tokenid = tok.id,
            complete = function(rollInfo)
                local total = rollInfo.total
                local nat = rollInfo.naturalRoll or 0
                if kind == "read" then
                    --discovery test resolves immediately by the rules.
                    local tier = NegotiationRules.TierForTotal(total)
                    NegotiationRun.Mutate("Read the NPC", function(l)
                        if tier >= 3 then
                            l.pendingReveal = { who = tok.charid, whoName = tok.name, kind = "" }
                            NegotiationRun.Log(l, tok.name, "", "read them - and learned something.", "good")
                        elseif tier == 2 then
                            NegotiationRun.Log(l, tok.name, "", "read them - and learned nothing.", "neutral")
                        else
                            l.patience = math.max(0, l.patience - 1)
                            NegotiationRun.Log(l, tok.name, "", "pushed too hard - he's losing patience.", "bad")
                        end
                        l.floor = ""
                    end)
                else
                    NegotiationRun.Mutate("Make an argument", function(l)
                        l.pending = {
                            who = tok.charid,
                            whoName = tok.name,
                            text = text,
                            roll = total,
                            natHigh = (nat >= 19),
                            angleTraitId = angleId or "",
                        }
                    end)
                end
                sayInput.text = ""
            end,
        }
    end

    local actionsPanel = gui.Panel{
        flow = "horizontal", width = "100%", height = "auto", vmargin = 8,
        gui.Button{
            classes = { "sizeM" }, width = 296, height = 36,
            text = "Make your case",
            refreshNeg = function(element, live)
                local blocked = live:try_get("pending", false)
                    or (live.floor ~= "" and not IHaveFloor(live))
                    or NegotiationRules.Terminal(live.interest, live.patience) ~= nil
                    or dmhub.currentToken == nil
                element:SetClass("hidden", dmhub.currentToken == nil)
                element:SetClass("disabled", blocked and true or false)
            end,
            click = function()
                MakeRoll("argue")
            end,
        },
        gui.Button{
            classes = { "sizeM" }, width = 190, height = 36, lmargin = 12,
            text = "Read them",
            refreshNeg = function(element, live)
                local blocked = live:try_get("pending", false)
                    or (live.floor ~= "" and not IHaveFloor(live))
                    or NegotiationRules.Terminal(live.interest, live.patience) ~= nil
                    or dmhub.currentToken == nil
                element:SetClass("hidden", dmhub.currentToken == nil)
                element:SetClass("disabled", blocked and true or false)
            end,
            click = function()
                MakeRoll("read")
            end,
        },
    }

    --Who has carried the scene. The rules give a negotiation no turn order, so
    --this NUDGES rather than gates: a hero who has not spoken reads as an
    --unspent resource, which is exactly what they are.
    local spokenPanel = gui.Panel{
        flow = "horizontal", width = "100%", height = "auto", wrap = true, vmargin = 4,
        refreshNeg = function(element, live)
            local children = {}
            local spoke = live:try_get("spoke", {})
            for _, token in ipairs(dmhub.allTokens) do
                if token.properties:IsHero() and token.ownerId ~= nil then
                    local n = spoke[token.charid] or 0
                    children[#children + 1] = gui.Label{
                        classes = { "sizeS" },
                        width = "auto", height = "auto", rmargin = 14, halign = "left",
                        fontSize = 11,
                        color = n > 0 and "#8a8a8a" or "#e4ddd0",
                        text = n > 0
                            and string.format("%s  argued %s", token.name,
                                n == 1 and "once" or string.format("%d times", n))
                            or string.format("%s  has not spoken", token.name),
                    }
                end
            end
            element.children = children
        end,
    }

    --tier-3 discovery: the roller picks the KIND only (never a browse of the
    --hidden list); the Director then picks which entry flips.
    local discoveryPanel = gui.Panel{
        flow = "vertical", width = "100%", height = "auto", vmargin = 6,
        refreshNeg = function(element, live)
            local pr = live:try_get("pendingReveal", false)
            local mine = pr and MyCharId() ~= nil and pr.who == MyCharId()
            element:SetClass("collapsed", not mine)
            if not mine then
                return
            end
            element.children = {
                gui.Label{
                    classes = { "sizeS", "bold" },
                    width = "100%", height = "auto", vmargin = 2,
                    text = "You read them. What did you learn?",
                },
                gui.Panel{
                    flow = "horizontal", width = "100%", height = "auto",
                    gui.Button{
                        classes = { "sizeS" }, width = "48%", height = 28,
                        text = "A motivation",
                        click = function()
                            NegotiationRun.Mutate("Discovery pick", function(l)
                                l.pendingReveal = { who = pr.who, whoName = pr.whoName, kind = "motivation" }
                            end)
                        end,
                    },
                    gui.Button{
                        classes = { "sizeS" }, width = "48%", height = 28, lmargin = 8,
                        text = "A pitfall",
                        click = function()
                            NegotiationRun.Mutate("Discovery pick", function(l)
                                l.pendingReveal = { who = pr.who, whoName = pr.whoName, kind = "pitfall" }
                            end)
                        end,
                    },
                },
            }
        end,
    }

    --The conversation: STORY BEATS only, one compact line each. The
    --spoken/typed line (when there is one) sits quoted beneath its beat -
    --never hidden behind a click, because for a hard-of-hearing player that
    --text IS the conversation. Bookkeeping lives in the rail's audit strip.
    local TONE_GLYPH = {
        good = "+", bad = "x", npc = "\"", system = "-", neutral = ">",
    }
    local TONE_COLOR = {
        good = "#4db88c", bad = "#c94040", npc = "#e4ddd0",
        system = "#7a7468", neutral = "#8a8a8a",
    }

    local historyPanel = gui.Panel{
        flow = "vertical", width = "100%", height = "auto", valign = "top",
        refreshNeg = function(element, live)
            local children = {}
            for i = #live.history, 1, -1 do
                local h = live.history[i]
                local tone = h.tone or "neutral"
                local col = TONE_COLOR[tone] or TONE_COLOR.neutral

                local rows = {}
                --the beat itself: glyph + who + cue, one line.
                local head = ""
                if (h.who or "") ~= "" then
                    head = h.who
                end
                if (h.cue or "") ~= "" then
                    head = head ~= "" and (head .. "  " .. h.cue) or h.cue
                end
                if head ~= "" then
                    rows[#rows + 1] = gui.Panel{
                        flow = "horizontal", width = "100%", height = "auto",
                        gui.Label{
                            classes = { "sizeS" },
                            width = 16, height = "auto", valign = "top",
                            fontSize = 12, color = col,
                            text = TONE_GLYPH[tone] or ">",
                        },
                        gui.Label{
                            classes = { "sizeS" },
                            width = "100%-16", height = "auto", textWrap = true,
                            fontSize = 12,
                            color = tone == "system" and "#7a7468" or "#c9c3b8",
                            text = head,
                        },
                    }
                end
                --what was actually said, quoted, when there is a line.
                if (h.text or "") ~= "" then
                    rows[#rows + 1] = gui.Label{
                        classes = { "sizeS" },
                        width = "100%-16", height = "auto", halign = "right",
                        textWrap = true, vmargin = 1,
                        fontSize = 13,
                        color = tone == "npc" and "#e4ddd0" or "#8a8a8a",
                        text = "\"" .. h.text .. "\"",
                    }
                end

                children[#children + 1] = gui.Panel{
                    flow = "vertical", width = "100%", height = "auto", vmargin = 3,
                    children = rows,
                }
            end
            element.children = children
        end,
    }

    --the offer: shape always standing, terms when revealed; accept row.
    --The left column is 400 and this box pads 12 a side, so its children are
    --sized to the 376 INNER width in px: a "100%" child would be measured
    --against the full 400 and hang past the padded edge (see the column note).
    local OFFER_W = 376
    local offerPanel = gui.Panel{
        flow = "vertical", width = "100%", height = "auto",
        valign = "bottom", vmargin = 8,
        hpad = 12, vpad = 10, borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#131315",
        border = 1,
        borderColor = "#ffffff47",
        refreshNeg = function(element, live)
            local terminal = NegotiationRules.Terminal(live.interest, live.patience)
            local o = live.offers[NegotiationRules.OfferIndex(live.interest)]
                or { terms = "", revealed = false }
            local children = {}

            local heading = string.format("His offer right now - \"%s\"",
                NegotiationRules.offerLabels[live.interest] or "")
            if terminal == "final" then
                heading = string.format("FINAL OFFER - \"%s\"",
                    NegotiationRules.offerLabels[live.interest] or "")
            elseif terminal == "nodeal" then
                heading = "NO DEAL - he offers nothing and ends it."
            end

            children[#children + 1] = gui.Label{
                classes = { "bold", "sizeS" },
                width = OFFER_W, height = "auto", halign = "left",
                color = terminal ~= nil and "#e8a030" or "#7a7468",
                text = heading,
            }

            --The next rung, in SHAPE only (the prepped terms stay the Director's
            --to reveal). Without it, accept-or-push is a coin flip: this is what
            --tells the table whether another argument is worth the patience.
            if terminal == nil and live.interest < NegotiationRules.MAX then
                children[#children + 1] = gui.Label{
                    classes = { "sizeS" },
                    width = OFFER_W, height = "auto", halign = "left",
                    textWrap = true, tmargin = 2,
                    fontSize = 11, color = "#7a7468",
                    text = string.format("Move him one more step and it becomes \"%s\"",
                        NegotiationRules.offerLabels[live.interest + 1] or ""),
                }
            end

            if terminal ~= "nodeal" then
                if o.revealed then
                    local terms = (o.terms or "")
                    if terms == "" then
                        terms = NegotiationRules.offerLabels[live.interest] or ""
                    end
                    children[#children + 1] = gui.Label{
                        classes = { "sizeM" },
                        width = OFFER_W, height = "auto", halign = "left",
                        textWrap = true, tmargin = 6, bmargin = 8,
                        text = terms,
                    }

                    --accept row: name + word + glyph, three-state.
                    local accepts = {}
                    for _, token in ipairs(dmhub.allTokens) do
                        if token.properties:IsHero() and token.ownerId ~= nil then
                            local state = live.accepted[token.charid]
                            local word = "- Waiting"
                            local col = "#7a7468"
                            if state == "accepted" then
                                word = "OK Accepted"; col = "#4db88c"
                            elseif state == "declined" then
                                word = "X Declined"; col = "#c94040"
                            end
                            accepts[#accepts + 1] = gui.Label{
                                classes = { "sizeS" },
                                width = "auto", height = "auto", rmargin = 12,
                                halign = "left",
                                fontSize = 12, color = col,
                                text = string.format("%s  %s", token.name, word),
                            }
                        end
                    end
                    children[#children + 1] = gui.Panel{
                        flow = "horizontal", width = OFFER_W, height = "auto",
                        halign = "left", wrap = true, bmargin = 6,
                        children = accepts,
                    }

                    local me = MyCharId()
                    if me ~= nil then
                        children[#children + 1] = gui.Panel{
                            flow = "horizontal", width = OFFER_W, height = "auto",
                            halign = "left",
                            --168 a side: the themed button carries its own
                            --hmargin, so two 180s + the gap overran the 376.
                            gui.Button{
                                classes = { "sizeS" }, width = 168, height = 28, halign = "left",
                                text = "Accept",
                                click = function()
                                    NegotiationRun.Mutate("Accept offer", function(l)
                                        l.accepted[me] = "accepted"
                                        local tok = dmhub.GetCharacterById(me)
                                        NegotiationRun.Log(l, "", "",
                                            string.format("%s accepted the offer.",
                                                tok ~= nil and tok.name or "A hero"), "system")
                                    end)
                                end,
                            },
                            gui.Button{
                                classes = { "sizeS" }, width = 168, height = 28,
                                lmargin = 8, halign = "left",
                                text = "Decline",
                                click = function()
                                    NegotiationRun.Mutate("Decline offer", function(l)
                                        l.accepted[me] = "declined"
                                        local tok = dmhub.GetCharacterById(me)
                                        NegotiationRun.Log(l, "", "",
                                            string.format("%s declined the offer.",
                                                tok ~= nil and tok.name or "A hero"), "system")
                                    end)
                                end,
                            },
                        }
                    end
                else
                    children[#children + 1] = gui.Label{
                        classes = { "sizeS" },
                        width = OFFER_W, height = "auto", halign = "left", tmargin = 6,
                        color = "#7a7468",
                        text = "He hasn't stated his terms yet.",
                    }
                end
            end

            element.children = children
        end,
    }

    local closeButton = nil
    if isDM then
        --floating: the dialog's flow is horizontal, so an in-flow close button
        --is a COLUMN - it was shoving the whole stage right by its own width
        --and stealing the left column's margin.
        closeButton = gui.Button{
            classes = { "closeButton" },
            floating = true,
            halign = "left", valign = "top",
            press = function()
                GameHud.HidePresentedDialog()
            end,
        }
    end

    local resultPanel
    resultPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = { "bordered", "bg" },
        width = 1100,
        height = 820,
        flow = "horizontal",
        blurBackground = true,
        monitorGame = doc.path,
        hpad = 20, vpad = 18, borderBox = true,

        closeButton,

        --Columns are FIXED px, not percentages: the dialog carries hpad, and
        --percentage children are measured against the full width (borderBox
        --does not inset them), so 40%+58% overflowed and clipped the right
        --column's buttons.
        --left column: identity, the read on the NPC, then the standing offer
        --pinned to the bottom (it is the thing the table decides on).
        --400 + 44 gutter + 596 = 1040, inside the dialog's 1060 usable width.
        --The gutter has to beat the dialog's own 20 edge padding by enough to
        --read as a gutter: at 24 the composer card looked stuck to the column.
        gui.Panel{
            flow = "vertical", width = 400, height = "100%", rmargin = 44,
            gui.Panel{
                flow = "vertical", width = "100%", height = "100%-250",
                vscroll = true,
                identityPanel,
                bandsPanel,
                patienceCue,
                patienceBudget,
                learnedPanel,
            },
            offerPanel,
        },

        --right column: composer card on top, history takes the remaining
        --height and scrolls inside it (height "100%" on the scroller would
        --exceed the column and spill past the dialog's bottom edge).
        --400 + 44 gutter + 560 = 1004 inside the 1060 usable width, so the
        --column pulls 56 back from the dialog's right edge. The children pack
        --LEFT, so every spare pixel lands on the right - the column's width IS
        --the right margin, and at 596 the composer card was hard against the frame.
        gui.Panel{
            flow = "vertical", width = 560, height = "100%",
            composerStatus,
            gui.Panel{
                flow = "vertical", width = "100%", height = "auto",
                hpad = 14, vpad = 12, borderBox = true, vmargin = 4,
                bgimage = "panels/square.png",
                bgcolor = "#131315",
                border = 1,
                borderColor = "#ffffff26",
                discoveryPanel,
                anglePanel,
                angleHelp,
                sayInput,
                attrPanel,
                actionsPanel,
            },
            spokenPanel,
            gui.Label{
                classes = { "bold" },
                width = "100%", height = "auto", vmargin = 8,
                fontSize = 12, color = "#7a7468",
                text = "HOW IT'S GOING",
            },
            gui.Panel{
                flow = "vertical", width = "100%", height = "100%-360",
                valign = "top",
                vscroll = true,
                historyPanel,
            },
        },

        refreshGame = function(element)
            doc = NegotiationRun.Doc()
            if doc == nil then
                return
            end
            m_live = doc.data.livedata
            if m_live == nil then
                return
            end
            element:FireEventTree("refreshNeg", m_live)
        end,

        refreshNegLocal = function(element)
            if m_live ~= nil then
                element:FireEventTree("refreshNeg", m_live)
            end
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    resultPanel:FireEventTree("refreshNeg", m_live)
    return resultPanel
end

GameHud.RegisterPresentableDialog{
    id = "negotiation",
    keeplocal = false,
    create = CreateNegotiationStage,
}

--==============================================================================
-- THE RAIL RUNNER -- Director-only dock panel. Everything is private here by
-- default; anything that can cross to the stage carries [Reveal], and anything
-- the players can see carries ON STAGE. The runner knows the rules so the
-- Director doesn't have to.
--==============================================================================

local function CreateNegotiationRunner()
    --pending-card selections (local to the Director's client).
    local m_track = nil       --"appeal" | "nomotivation" | "pitfall"
    local m_trackTrait = nil  --trait id for appeal/pitfall
    local m_tier = nil        --override; nil = from the roll
    local m_lie = false
    local m_repeat = false    --nomotivation track: they have made this argument before

    local runnerPanel

    local function Refresh()
        if runnerPanel ~= nil and runnerPanel.valid then
            runnerPanel:FireEvent("refreshRunner")
        end
    end

    --small helpers ---------------------------------------------------------
    local function Micro(text, col)
        return gui.Label{
            classes = { "sizeS" },
            width = "100%", height = "auto", vmargin = 2,
            fontSize = 11, color = col or "#7a7468",
            textWrap = true,
            text = text,
        }
    end

    local function SmallButton(text, onclick, wide)
        return gui.Button{
            classes = { "sizeS" },
            width = wide or 96, height = 24, margin = 2,
            text = text,
            click = onclick,
        }
    end

    ------------------------------------------------------------------------
    -- The idle state: no negotiation running. Offers both entry paths.
    ------------------------------------------------------------------------
    local function IdleChildren()
        local children = {}
        children[#children + 1] = Micro(
            "No negotiation running. Begin one from a Negotiation page in the journal, the Run panel - or start a quick one here.")

        local nameInput = gui.Input{
            classes = { "sizeS" },
            width = "96%", height = 26, vmargin = 4,
            placeholderText = "Who are they? (e.g. Gate guard)",
            text = "",
        }
        children[#children + 1] = nameInput

        local m_attitude = "suspicious"
        local m_archetype = nil

        local attitudeOptions = {}
        for _, a in ipairs(NegotiationRules.attitudes) do
            attitudeOptions[#attitudeOptions + 1] = {
                id = a.id,
                text = string.format("%s (I%d P%d)", a.name, a.interest, a.patience),
            }
        end

        children[#children + 1] = gui.Dropdown{
            classes = { "sizeS" },
            width = "96%", height = 28, vmargin = 3,
            options = attitudeOptions,
            idChosen = m_attitude,
            change = function(element)
                m_attitude = element.idChosen
            end,
        }

        local archetypeButton
        archetypeButton = gui.Button{
            classes = { "sizeS" },
            width = "96%", height = 26, vmargin = 3,
            text = "Seed from an archetype...",
            click = function(element)
                local entries = { {
                    text = "(none)",
                    click = function()
                        element.popup = nil
                        m_archetype = nil
                        archetypeButton.text = "Seed from an archetype..."
                    end,
                } }
                local list = {}
                for id, neg in unhidden_pairs(dmhub.GetTable(Negotiator.tableName) or {}) do
                    list[#list + 1] = neg
                end
                table.sort(list, function(a, b)
                    return (a:try_get("impressionScore", 1)) < (b:try_get("impressionScore", 1))
                end)
                for _, neg in ipairs(list) do
                    local negotiator = neg
                    entries[#entries + 1] = {
                        text = string.format("%d  %s", negotiator:try_get("impressionScore", 1), negotiator.name),
                        click = function()
                            element.popup = nil
                            m_archetype = negotiator
                            archetypeButton.text = negotiator.name
                        end,
                    }
                end
                element.popup = gui.ContextMenu{ entries = entries }
            end,
        }
        children[#children + 1] = archetypeButton

        children[#children + 1] = gui.Button{
            classes = { "sizeM" },
            width = "96%", height = 30, vmargin = 6,
            text = "Quick negotiation",
            click = function(element)
                local name = nameInput.text
                if name == nil or name == "" then
                    name = "Negotiation"
                end
                --a stub prep doc behind the scenes, so even a 3-minute scene
                --gets a home for its record.
                local doc = NegotiationDocument.CreateNew{
                    description = name,
                    npcName = name,
                    attitude = m_attitude,
                }
                if m_archetype ~= nil then
                    doc:SeedFromArchetype(m_archetype)
                end
                doc:Upload()
                NegotiationRun.Begin(doc, element)
                Refresh()
            end,
        }

        return children
    end

    ------------------------------------------------------------------------
    -- The running state.
    ------------------------------------------------------------------------
    local function RunningChildren(live)
        local children = {}
        local npc = live.npcName ~= "" and live.npcName or "the NPC"
        local terminal = NegotiationRules.Terminal(live.interest, live.patience)

        -- 1. Header ---------------------------------------------------------
        local portrait = live:try_get("portrait", "")
        children[#children + 1] = gui.Panel{
            flow = "horizontal", width = "100%", height = "auto", vmargin = 2,
            (portrait ~= "") and gui.Panel{
                classes = { "image" },
                width = 34, height = 42, valign = "top", rmargin = 8,
                bgcolor = "white",
                bgimage = portrait,
                borderWidth = 1,
                borderColor = "#ffffff47",
            } or nil,
            gui.Panel{
                flow = "vertical", width = "100%-46", height = "auto", valign = "center",
                gui.Label{
                    classes = { "bold", "sizeM" },
                    width = "100%", height = "auto", textWrap = true,
                    text = npc,
                },
                --what he IS, not just who: the archetype the run is playing and
                --how hard he is to move. Director-side only.
                (live:try_get("archetype", "") ~= "") and Micro(string.format(
                    "%s - impression %d", live.archetype, live:try_get("impression", 1)),
                    "#8a8a8a") or nil,
                (not live.nameRevealed) and Micro("Unnamed on stage (\"???\")", "#e8a030") or nil,
            },
        }
        if terminal ~= nil then
            children[#children + 1] = Micro(terminal == "nodeal"
                and "TERMINAL - no deal; he offers nothing."
                or "TERMINAL - final offer on stage.", "#e8a030")
        end

        -- The "Now:" coach line ---------------------------------------------
        children[#children + 1] = gui.Label{
            classes = { "sizeS" },
            width = "100%", height = "auto", vmargin = 4,
            hpad = 8, vpad = 6, borderBox = true,
            bgimage = "panels/square.png",
            bgcolor = "#1a1a1e",
            border = 1, borderColor = "#ffffff26",
            textWrap = true,
            fontSize = 12,
            text = "Now: " .. NegotiationRun.CoachLine(live),
        }

        children[#children + 1] = gui.Panel{
            flow = "horizontal", width = "100%", height = "auto", wrap = true, vmargin = 2,
            SmallButton(live.showRaw and "Hide the numbers" or "Reveal the numbers", function()
                NegotiationRun.Mutate("Toggle numbers", function(l)
                    l.showRaw = not l.showRaw
                    NegotiationRun.Audit(l, l.showRaw and "Numbers revealed" or "Numbers hidden")
                end)
                Refresh()
            end, 130),
            SmallButton("End negotiation", function()
                local doc = NegotiationRun.Doc()
                local l = doc ~= nil and doc.data.livedata or nil
                if l ~= nil then
                    --record: campaign ledger + a summary on the prep doc.
                    local outcome = "walked away"
                    local anyAccept = false
                    for _, v in pairs(l.accepted) do
                        if v == "accepted" then anyAccept = true end
                    end
                    if anyAccept then
                        outcome = string.format("deal struck - \"%s\"",
                            NegotiationRules.offerLabels[l.interest] or "")
                    elseif l.interest <= 0 then
                        outcome = "no deal"
                    end

                    local summaryLine = string.format("%s: %s (Interest %d)",
                        npc, outcome, l.interest)
                    pcall(function()
                        CampaignState.Apply({}, summaryLine)
                    end)

                    local prep = (dmhub.GetTable(CustomDocument.tableName) or {})[l.docid]
                    if prep ~= nil then
                        local learned = {}
                        for _, t in ipairs(l.traits) do
                            if t.revealed then
                                learned[#learned + 1] = t.name
                            end
                        end
                        local summaries = prep:get_or_add("summaries", {})
                        summaries[#summaries + 1] = string.format(
                            "**Run:** %s. Final Interest %d, Patience %d. Revealed: %s.",
                            outcome, l.interest, l.patience,
                            #learned > 0 and table.concat(learned, ", ") or "nothing")
                        prep:Upload()
                    end
                end
                GameHud.HidePresentedDialog()
                Refresh()
            end, 120),
        }

        -- 2. Meters ---------------------------------------------------------
        local function MeterRow(label, value, which)
            return gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", vmargin = 2,
                gui.Label{
                    classes = { "sizeS" }, width = 70, height = 24, valign = "center",
                    text = label,
                },
                gui.Label{
                    classes = { "bold" }, width = 40, height = 24, valign = "center",
                    textAlignment = "center",
                    text = string.format("%d/5", value),
                },
                SmallButton("-", function()
                    NegotiationRun.AdjustMeter(which, -1)
                    Refresh()
                end, 30),
                SmallButton("+", function()
                    NegotiationRun.AdjustMeter(which, 1)
                    Refresh()
                end, 30),
            }
        end
        children[#children + 1] = MeterRow("Interest", live.interest, "interest")
        children[#children + 1] = MeterRow("Patience", live.patience, "patience")

        -- 3. Pending argument card ------------------------------------------
        local pending = live:try_get("pending", false)
        if pending then
            local rollTier = NegotiationRules.TierForTotal(pending.roll or 0)
            local tier = m_tier or rollTier

            --default the track from the player's chosen angle.
            if m_track == nil then
                local angleId = pending.angleTraitId or ""
                if angleId ~= "" then
                    m_track = "appeal"
                    m_trackTrait = angleId
                else
                    m_track = "nomotivation"
                end
            end

            local cardChildren = {}
            cardChildren[#cardChildren + 1] = gui.Label{
                classes = { "bold", "sizeS" },
                width = "100%", height = "auto",
                text = string.format("%s rolled %d  (tier %d)",
                    pending.whoName or "A hero", pending.roll or 0, rollTier),
            }
            if (pending.text or "") ~= "" then
                cardChildren[#cardChildren + 1] = Micro("\"" .. pending.text .. "\"", "#8a8a8a")
            end

            --track radios
            local function TrackRow(id, text, traitId)
                local selected = (m_track == id) and (traitId == nil or m_trackTrait == traitId)
                return gui.Label{
                    classes = { "sizeS", "hoverable" },
                    width = "96%", height = "auto",
                    hpad = 8, vpad = 5, margin = 2, borderBox = true,
                    bgimage = "panels/square.png",
                    bgcolor = selected and "#ffffff1f" or "#00000000",
                    border = 1,
                    borderColor = selected and "#ffffff99" or "#ffffff47",
                    fontSize = 12,
                    textWrap = true,
                    text = text,
                    press = function()
                        m_track = id
                        m_trackTrait = traitId
                        if id ~= "nomotivation" then
                            m_repeat = false
                        end
                        Refresh()
                    end,
                }
            end

            for _, t in ipairs(live.traits) do
                if t.kind == "motivation" then
                    cardChildren[#cardChildren + 1] = TrackRow("appeal",
                        string.format("Appeals to: %s%s", t.name,
                            t.used and "  (already appealed - patience only)" or ""),
                        t.id)
                end
            end
            cardChildren[#cardChildren + 1] = TrackRow("nomotivation", "No motivation", nil)
            for _, t in ipairs(live.traits) do
                if t.kind == "pitfall" then
                    cardChildren[#cardChildren + 1] = TrackRow("pitfall",
                        string.format("Hits pitfall: %s", t.name), t.id)
                end
            end

            --tier override row
            local tierChildren = { gui.Label{
                classes = { "sizeS" }, width = 40, height = 24, valign = "center",
                fontSize = 11, text = "Tier",
            } }
            for t = 1, 3 do
                local tv = t
                local sel = (tier == tv)
                tierChildren[#tierChildren + 1] = gui.Label{
                    classes = { "sizeS", "hoverable" },
                    width = 34, height = 24, margin = 2, borderBox = true,
                    textAlignment = "center", fontSize = 12,
                    bgimage = "panels/square.png",
                    bgcolor = sel and "#ffffff1f" or "#00000000",
                    border = 1,
                    borderColor = sel and "#ffffff99" or "#ffffff47",
                    text = tostring(tv),
                    press = function()
                        m_tier = tv
                        Refresh()
                    end,
                }
            end
            if pending.natHigh then
                tierChildren[#tierChildren + 1] = Micro("nat 19-20: no patience cost", "#e8a030")
            end
            cardChildren[#cardChildren + 1] = gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", wrap = true, vmargin = 3,
                children = tierChildren,
            }

            --outcome preview: exactly what Resolve will do (kills the tables).
            local previewTrait = m_trackTrait ~= nil and NegotiationRun.TraitById(live, m_trackTrait) or nil
            local repeated = false
            if m_track == "appeal" then
                repeated = previewTrait ~= nil and previewTrait.used == true
            elseif m_track == "nomotivation" then
                repeated = m_repeat
            end
            local d = NegotiationRules.Resolve{
                track = m_track,
                tier = tier,
                repeated = repeated,
                natHigh = pending.natHigh,
                lie = m_lie,
            }
            local ni, np = NegotiationRules.ApplyDelta(live.interest, live.patience, d)
            local function fmt(n)
                if n > 0 then return "+" .. n end
                return tostring(n)
            end
            cardChildren[#cardChildren + 1] = gui.Label{
                classes = { "sizeS" },
                width = "96%", height = "auto", vmargin = 4,
                hpad = 8, vpad = 6, borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = "#0a0a0b",
                border = 1, borderColor = "#ffffff47",
                textWrap = true, fontSize = 12,
                text = string.format("Will apply: Interest %s, Patience %s  ->  he'll be %s (%d/%d)",
                    fmt(d.interest), fmt(d.patience), NegotiationRules.bands[ni] or "", ni, np),
            }

            --the repeat checkbox only exists on the track its rule lives on:
            --a no-motivation argument the heroes have already made auto-lands
            --on tier 1. (An already-appealed MOTIVATION needs no checkbox --
            --the runner tracks that itself.)
            if m_track == "nomotivation" then
                cardChildren[#cardChildren + 1] = gui.Check{
                    classes = { "sizeS" },
                    width = "96%", height = 22, minWidth = 0,
                    text = "Repeated argument (auto tier 1)",
                    value = m_repeat,
                    change = function(element)
                        m_repeat = element.value
                        Refresh()
                    end,
                }
            end

            --the lie checkbox only exists when its rule condition holds.
            if d.interest <= 0 or m_lie then
                cardChildren[#cardChildren + 1] = gui.Check{
                    classes = { "sizeS" },
                    width = "96%", height = 22,
                    text = "Caught in a lie (extra Interest -1)",
                    value = m_lie,
                    change = function(element)
                        m_lie = element.value
                        Refresh()
                    end,
                }
            end

            cardChildren[#cardChildren + 1] = gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", vmargin = 4,
                SmallButton("Resolve", function()
                    NegotiationRun.ResolvePending{
                        track = m_track,
                        tier = tier,
                        traitId = m_trackTrait,
                        lie = m_lie,
                        repeated = m_repeat,
                    }
                    m_track = nil; m_trackTrait = nil; m_tier = nil; m_lie = false; m_repeat = false
                    Refresh()
                end, 96),
                SmallButton("Dismiss", function()
                    NegotiationRun.DismissPending()
                    m_track = nil; m_trackTrait = nil; m_tier = nil; m_lie = false; m_repeat = false
                    Refresh()
                end, 96),
            }

            children[#children + 1] = gui.Panel{
                flow = "vertical", width = "100%", height = "auto", vmargin = 6,
                hpad = 8, vpad = 8, borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = "#1a1a1e",
                border = 1, borderColor = "#ffffff47",
                children = cardChildren,
            }
        else
            --[+ Log argument]: a roll-less argument (exceptional roleplay).
            children[#children + 1] = SmallButton("+ Log argument", function()
                NegotiationRun.Mutate("Log argument", function(l)
                    l.pending = {
                        who = "", whoName = "A hero", text = "",
                        roll = 17, natHigh = false, angleTraitId = "",
                    }
                end)
                m_tier = 3 --roleplay defaults to the auto-tier-3 the book grants.
                Refresh()
            end, "96%")
        end

        -- 4. Discovery pick pending -----------------------------------------
        local pr = live:try_get("pendingReveal", false)
        if pr and (pr.kind or "") ~= "" then
            local kindName = pr.kind == "pitfall" and "pitfall" or "motivation"
            local pickChildren = { Micro(string.format(
                "%s learned a %s - which one?", pr.whoName or "A hero", kindName), "#e4ddd0") }
            for _, t in ipairs(live.traits) do
                if t.kind == pr.kind and not t.revealed then
                    local trait = t
                    pickChildren[#pickChildren + 1] = SmallButton(trait.name, function()
                        NegotiationRun.Mutate("Reveal discovery", function(l)
                            local tt = NegotiationRun.TraitById(l, trait.id)
                            if tt ~= nil then
                                tt.revealed = true
                            end
                            l.pendingReveal = false
                        end)
                        Refresh()
                    end, "96%")
                end
            end
            children[#children + 1] = gui.Panel{
                flow = "vertical", width = "100%", height = "auto", vmargin = 6,
                hpad = 8, vpad = 8, borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = "#1a1a1e",
                border = 1, borderColor = "#e8a030",
                children = pickChildren,
            }
        elseif pr then
            children[#children + 1] = Micro(string.format("Awaiting %s's discovery pick.",
                pr.whoName or "the hero"), "#e8a030")
        end

        -- 5. Motivations & pitfalls: the reveal grammar ----------------------
        children[#children + 1] = gui.Label{
            classes = { "bold" },
            width = "100%", height = "auto", vmargin = 4,
            fontSize = 12, color = "#7a7468",
            text = "MOTIVATIONS & PITFALLS",
        }
        for _, t in ipairs(live.traits) do
            local trait = t
            local rowChildren = {
                gui.Label{
                    classes = { "sizeS" },
                    width = "100%", height = "auto", textWrap = true,
                    fontSize = 12,
                    text = string.format("%s  %s%s",
                        trait.kind == "pitfall" and "x" or "+",
                        trait.name,
                        trait.used and "  (used)" or ""),
                },
            }
            if (trait.line or "") ~= "" then
                rowChildren[#rowChildren + 1] = Micro("\"" .. trait.line .. "\"", "#8a8a8a")
            end
            local actions = {}
            if trait.revealed then
                actions[#actions + 1] = gui.Label{
                    classes = { "sizeS" },
                    width = "auto", height = "auto", valign = "center",
                    hpad = 6, vpad = 2, rmargin = 4, borderBox = true,
                    fontSize = 10, color = "#e4ddd0",
                    bgimage = "panels/square.png", bgcolor = "#ffffff1f",
                    text = "ON STAGE",
                }
                actions[#actions + 1] = SmallButton("Hide", function()
                    NegotiationRun.SetTraitRevealed(trait.id, false)
                    Refresh()
                end, 60)
            else
                actions[#actions + 1] = SmallButton("Reveal", function()
                    NegotiationRun.SetTraitRevealed(trait.id, true)
                    Refresh()
                end, 70)
            end
            if (trait.line or "") ~= "" then
                actions[#actions + 1] = SmallButton("Say it", function()
                    NegotiationRun.Mutate("NPC speaks", function(l)
                        NegotiationRun.Log(l, npc, trait.line, "", "npc")
                    end)
                    Refresh()
                end, 60)
            end
            rowChildren[#rowChildren + 1] = gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", wrap = true,
                children = actions,
            }
            children[#children + 1] = gui.Panel{
                flow = "vertical", width = "96%", height = "auto", vmargin = 3,
                hpad = 6, vpad = 6, borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = "#131315",
                border = 1, borderColor = "#ffffff26",
                children = rowChildren,
            }
        end

        -- 6. Offers ladder ---------------------------------------------------
        children[#children + 1] = gui.Label{
            classes = { "bold" },
            width = "100%", height = "auto", vmargin = 4,
            fontSize = 12, color = "#7a7468",
            text = "OFFERS",
        }
        for i = NegotiationRules.MAX, 0, -1 do
            local interest = i
            local o = live.offers[NegotiationRules.OfferIndex(interest)]
                or { terms = "", revealed = false }
            local isCurrent = (interest == live.interest)
            local terms = (o.terms or "")
            local shown = terms ~= "" and terms or NegotiationRules.offerLabels[interest]
            local rowChildren = {
                gui.Label{
                    classes = { "sizeS" },
                    width = "100%", height = "auto", textWrap = true, fontSize = 12,
                    color = isCurrent and "#f2ede1" or "#8a8a8a",
                    text = string.format("%s%d  \"%s\"  %s",
                        isCurrent and "> CURRENT  " or "",
                        interest,
                        NegotiationRules.offerLabels[interest],
                        terms ~= "" and ("- " .. terms) or ""),
                },
            }
            if isCurrent then
                local actions = {}
                if o.revealed then
                    actions[#actions + 1] = gui.Label{
                        classes = { "sizeS" },
                        width = "auto", height = "auto", valign = "center",
                        hpad = 6, vpad = 2, rmargin = 4, borderBox = true,
                        fontSize = 10, color = "#e4ddd0",
                        bgimage = "panels/square.png", bgcolor = "#ffffff1f",
                        text = "ON STAGE",
                    }
                else
                    actions[#actions + 1] = SmallButton("Reveal terms", function()
                        NegotiationRun.Mutate("Reveal offer", function(l)
                            local idx = NegotiationRules.OfferIndex(l.interest)
                            local off = l.offers[idx] or { terms = "", revealed = false }
                            off.revealed = true
                            l.offers[idx] = off
                            NegotiationRun.Log(l, npc, off.terms ~= "" and off.terms
                                or (NegotiationRules.offerLabels[l.interest] or ""),
                                "states his terms.", "npc")
                        end)
                        Refresh()
                    end, 110)
                end
                rowChildren[#rowChildren + 1] = gui.Panel{
                    flow = "horizontal", width = "100%", height = "auto", wrap = true,
                    children = actions,
                }
            end
            children[#children + 1] = gui.Panel{
                flow = "vertical", width = "96%", height = "auto", vmargin = 2,
                hpad = 6, vpad = 5, borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = isCurrent and "#1a1a1e" or "#00000000",
                border = 1,
                borderColor = isCurrent and "#ffffff47" or "#ffffff14",
                children = rowChildren,
            }
        end

        -- 7. The audit strip: Director-only bookkeeping (meter corrections,
        -- the numbers toggle, floor churn). Deliberately NOT on the stage - a
        -- fat-finger fix must not read to the table as an NPC mood swing.
        local audit = live:try_get("audit", {})
        if #audit > 0 then
            children[#children + 1] = gui.Label{
                classes = { "bold" },
                width = "100%", height = "auto", vmargin = 6,
                fontSize = 12, color = "#7a7468",
                text = "AUDIT (you only)",
            }
            local shown = 0
            for i = #audit, 1, -1 do
                if shown >= 8 then
                    break
                end
                shown = shown + 1
                children[#children + 1] = Micro("- " .. (audit[i].text or ""), "#7a7468")
            end
        end

        return children
    end

    ------------------------------------------------------------------------
    runnerPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        --the shared presentdialog doc carries the live negotiation; every
        --client's change to it re-renders the rail. MUST come from GameHud:
        --shared docs are namespaced per module, so our own mod's
        --"presentdialog" would be a different, never-changing document.
        monitorGame = GameHud.PresentDialogPath(),

        refreshRunner = function(element)
            local doc = NegotiationRun.Doc()
            local live = doc ~= nil and doc.data.livedata or nil
            if live == nil then
                element.children = IdleChildren()
            else
                element.children = RunningChildren(live)
            end
        end,

        refreshGame = function(element)
            element:FireEvent("refreshRunner")
        end,

        create = function(element)
            element:FireEvent("refreshRunner")
        end,
    }

    return runnerPanel
end

DockablePanel.Register{
    name = "Negotiation",
    icon = "icons/standard/Icon_App_Negotiation.png",
    minHeight = 260,
    vscroll = true,
    dmonly = true,
    content = function()
        return CreateNegotiationRunner()
    end,
}
