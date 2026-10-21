--| Shared improvement-request profile from okf-profiles v0.22.0.
--
-- Source: mori://shinzui/okf-profiles/profiles/improvement-requests
--
-- Loading this descriptor requires `okf` 0.9.0.0 or later. The profile targets
-- Open Knowledge Format v0.2: every request carries a `generated` mapping whose
-- `by` is an OKF §7 actor, and the bundle root declares `okf_version: "0.2"`
-- (write it with `okf index docs/improvement-requests --write --okf-version 0.2`).
--
-- The integrity hash below is the semantic hash of the v0.22.0 package. When
-- bumping to a future release, change the tag, delete the hash line, and re-run:
--
--     dhall freeze docs/improvement-requests/profile.dhall
--
-- Never hand-write a `sha256:` value, and never delete a hash from a frozen
-- import to make it resolve.
let Profiles =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.22.0/package.dhall
        sha256:2294a5bd32ca22daa89610e12fde81dd3115701fcb0bf7a790c7bdee6d85db65

in  Profiles.coordination.improvementRequests
