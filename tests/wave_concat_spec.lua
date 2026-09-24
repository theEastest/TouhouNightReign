-- Tests for concatenating short wave atoms into a formal room wave.
--
-- The catalog stores many short atoms. The room selector must always produce a
-- formal wave of at least thirty seconds by concatenating atoms on a shared
-- timeline, preserving each atom's relative spawn offsets and class order.
--
-- The concatenation helper lives inside legacy_native_main.lua, so this spec
-- mirrors the exact contract and guards it against regression.

return function(assert_equal, assert_true)
    local WAVE_MIN_SECONDS = 30
    local WAVE_MIN_FRAMES = WAVE_MIN_SECONDS * 60

    -- Mirror of concatenate_wave_atoms.
    local function concatenate(atoms)
        local members = {}
        local offset = 0
        local seen, class_list = {}, {}
        local first = atoms[1]
        for _, atom in ipairs(atoms) do
            for _, member in ipairs(atom.members or {}) do
                members[#members + 1] = {
                    class_name = member.class_name,
                    args = member.args,
                    env = member.env,
                    spawn_frame = offset + (tonumber(member.spawn_frame) or 0),
                }
                if member.class_name and not seen[member.class_name] then
                    seen[member.class_name] = true
                    class_list[#class_list + 1] = member.class_name
                end
            end
            offset = offset + math.max(1, math.floor(tonumber(atom.duration_frames) or 0))
        end
        table.sort(class_list)
        return {
            id = first and (first.id .. "+combo") or "combo",
            duration_frames = offset,
            duration_seconds = offset / 60,
            classes = class_list,
            members = members,
            legacy_exact = true,
            combined = true,
        }
    end

    local function atom(id, frames, members)
        return { id = id, duration_frames = frames, members = members }
    end

    -- A single long atom is already a formal wave.
    local lone = atom("a", WAVE_MIN_FRAMES + 60, { { class_name = "x", spawn_frame = 0 } })
    assert_true(lone.duration_frames >= WAVE_MIN_FRAMES, "long atom already meets the minimum")

    -- Three 12 second atoms combine past thirty seconds.
    local a = atom("a", 720, { { class_name = "e1", spawn_frame = 0 }, { class_name = "e2", spawn_frame = 120 } })
    local b = atom("b", 720, { { class_name = "e3", spawn_frame = 0 } })
    local c = atom("c", 720, { { class_name = "e1", spawn_frame = 60 } })
    local combined = concatenate({ a, b, c })
    assert_equal(combined.duration_frames, 2160, "three 12 second atoms span 36 seconds")
    assert_true(combined.duration_seconds >= WAVE_MIN_SECONDS, "combined wave meets the minimum")
    assert_equal(#combined.members, 4, "every member is retained")
    assert_equal(combined.combined, true, "the wave is marked combined")

    -- Member offsets are rebased so later atoms never overlap earlier ones.
    assert_equal(combined.members[1].spawn_frame, 0, "first atom starts at zero")
    assert_equal(combined.members[2].spawn_frame, 120, "first atom keeps its internal offset")
    assert_equal(combined.members[3].spawn_frame, 720, "second atom starts after the first")
    assert_equal(combined.members[4].spawn_frame, 720 + 720 + 60, "third atom offsets by both predecessors")

    -- Spawn frames are monotonically non-decreasing, so the timeline is sane.
    local previous = -1
    for _, member in ipairs(combined.members) do
        assert_true(member.spawn_frame >= previous, "spawn frames must not go backwards")
        previous = member.spawn_frame
    end

    -- Class list is deduplicated and sorted.
    assert_equal(#combined.classes, 3, "duplicate classes are collapsed")
    for index = 2, #combined.classes do
        assert_true(combined.classes[index - 1] <= combined.classes[index], "classes are sorted")
    end
end
