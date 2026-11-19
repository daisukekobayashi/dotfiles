# Detail Reads

Triage places every item from cheap list data first, and reads an item's full
text only where the recommendation depends on it. This file owns which items
get a detail read. The calling skill owns the provider commands for each pass
and where each signal is read.

These rules depend only on list fields and native relationships, never on how
a project writes its item descriptions, so they hold for any template or none.

## Overview

Before reading any item description, place every open item from:

- the list fields the calling skill fetches, such as title, labels or tags,
  milestone or iteration, priority, and update time;
- native blocking and parent-child relationships, each reduced to the related
  item's ID and state;
- the repository guidance read for the lens basis.

Give each item a provisional class and a provisional rank under the lens. An
item with an open native blocker is blocked, and a parent with open children
is a tracker, without a detail read.

## Detail band

Read the full text, description and comments, of every item in the **detail
band**:

- the item the overview ranks next, the items it would run in parallel with,
  and the items of the next wave;
- any open item natively blocked by a band item, because a lens can rank a
  blocker by the work it unblocks;
- any item whose overview placement turns on a fact only its text can hold,
  such as a title that names it a follow-up of another open item.

Request only the text and state; the list already gave the other fields.

A detail read can move an item or change a signal its blockers inherit, for
example when a `Blocked by` line names an open item, a comment says the item
was superseded or release-blocking, a read puts it on the core path, or the
touched areas overlap another band item. Whenever a read changes an item's
class, severity, or core-path standing, re-place it together with the items
that block it, natively or by text, because their rank can follow from what
they unblock. Then extend the band down the overview order until it again
holds the next item, its parallel items, and the next wave. The band is
complete when a pass adds no item.

Name parallel groups only among band items, whose touched areas were read.
List other current-wave items as unverified for parallel work.

Items outside the band keep their overview placement. A dependency or
severity written only in such an item's text stays unread, and can change a
ranking only through that item; the report's list-only items show where. The
user can name more items, or all of them, for a detail read.

## Report line

Add under `Current State`:

```markdown
- Detail reads: <items read in full>; list only: <items placed from list data, or "none">
```
