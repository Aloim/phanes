<!-- DOC | The canonical doc-discipline header block every documentation file carries, fetched so sessions and generated scripts quote one tested source; phanes.md Phase 2.5 Step 2b is the authoritative wording. -->
<!-- phanes-template v3.4.0 doc-header -->
<!-- The canonical doc-discipline header block (phanes.md Phase 2.5 Step 2b), fetched so the
     session and fallback-generated scripts quote one tested source instead of re-deriving it.
     `phanes scaffold` verifies its presence; the block is instantiated by whoever authors a
     documentation file (the first line takes that file's own one-line description). -->
<!-- SECTION doc-discipline-header -->
<!-- DOC | <one-line description: the question this file answers> -->
<!-- DOC DISCIPLINE | Soft ceiling: 500 lines. One topic per file; structure under ## headings.
     The DOC line above feeds `phanes doc-index`, keep it accurate; it is this file's line in _index.md.
     If this file exceeds the ceiling: split it into a same-named folder of focused topic files;
     carry both header lines into every part; update every inbound reference in the same change set;
     finish by running `phanes doc-index`.
     Consumers: NEVER bulk-read documentation folders, read _index.md first, load only what you need.
     Audit: `phanes doc-check`. -->
<!-- END SECTION -->
