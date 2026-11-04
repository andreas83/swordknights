extends GutTest
## The catalogue and the bible agree (docs/campaign.md): every chapter carries
## its inscription -- the masons' voice, one per chapter, read in order as the
## backstory -- with the words the bible's table gives it, in a secret room of
## the chapter's own level.
##
## The hour each level is set at is held to the catalogue by
## tests/unit/test_campaign_catalogue.gd, and each entry's par and clear-run
## time to the bible's "The campaign, played" by tests/unit/test_campaign_run.gd.
## This holds the third thing the bible promises of every chapter. The table
## is read out of the bible itself, so a line changed on one side and not the
## other fails here.

const BIBLE := "res://docs/campaign.md"


## numeral -> [line one, line two], from the bible's inscription table.
func _bible_inscriptions() -> Dictionary:
	var out := {}
	var row := RegEx.create_from_string(
		"^\\| (I|II|III|IV|V) \\| ([A-Z ]+) / ([A-Z ]+) \\| ")
	for line: String in FileAccess.get_file_as_string(BIBLE).split("\n"):
		var hit := row.search(line)
		if hit != null:
			out[hit.get_string(1)] = [hit.get_string(2).strip_edges(),
				hit.get_string(3).strip_edges()]
	return out


func test_every_chapter_carries_the_bible_s_inscription() -> void:
	var bible := _bible_inscriptions()
	assert_eq(bible.size(), 5, "the bible's table names five inscriptions")
	var chapters := 0
	for index: int in Campaign.count():
		var entry := Campaign.entry(index)
		if bool(entry["finale"]) or not Campaign.is_built(index):
			continue
		chapters += 1
		var numeral := String(entry["numeral"])
		var level := AsciiLevel.from_file(String(entry["file"]))
		var marks := level.entities.filter(func(mark: Dictionary) -> bool:
			return String(mark["kind"]) == "inscription")
		assert_eq(marks.size(), 1, "chapter %s has one inscription" % numeral)
		for mark: Dictionary in marks:
			assert_true(level.secret_at(mark["cell"]) >= 0,
				"chapter %s's inscription is in a secret room" % numeral)
		var words := Inscription.text_for(level.name, 0)
		assert_eq(Array(words), bible.get(numeral, []),
			"chapter %s says what the bible says it says" % numeral)
	assert_eq(chapters, 5, "five chapters")
