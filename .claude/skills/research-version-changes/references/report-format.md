# Report format

The report is a file in this shape. Every section stands on its own, so a caller can post a
subset of sections (for example on a Renovate pull request) and each still reads correctly.
Keep the section titles and the item layout stable, because callers select sections by
title.

```markdown
## <deployable>: <FROM> → <TO>

<Bottom line, one sentence. How many required changes, deprecations, behaviour changes and
adoption candidates there are, and the single most important item. "No required changes
found" only when Coverage shows the range was actually read.>

### Required changes

1. **<title naming the exact key, flag or resource>** (<kind>, <version>)
   - Change: <old form → new form, precisely>
   - Affects the usage: <yes | no | unknown>. <evidence: file path and key, or what would settle it>
   - Action: <what to change, and where>
   - Source: <link, or the file and tag read directly>

   > <verbatim upstream instruction, only when its wording is the instruction>

### Deprecations to plan for

<same item layout. The kind is deprecated, and the version gives the announced removal
version when upstream states one>

### Behaviour to know about

- **<what changes>** (<version>). <what someone operating it will notice, and why no
  configuration change is needed>. <link>

### Worth adopting

<same item layout, with "Fits the usage" in place of "Affects the usage", saying what it
would improve for that use>

### Checked, not affecting the usage

- <change> (<version>). <why it does not touch the usage>

### Coverage

| Source | Range | Result |
| --- | --- | --- |
| <e.g. chart releases, owner/repo, tag family> | <versions> | <n read, n missing, n thin> |

App: <for a chart whose appVersion moved, the app version range in use, and whether the chart
notes appear to cover the app's changes>

Not checked: <every source not read and every configuration surface not seen>

### Approach notes

<What was tried that did not work, what eventually did, and anything notable that was not
asked about. For the caller. Not meant for posting.>
```

Kinds for required items are `breaking`, `removed`, `renamed`, `default-changed`,
`new-requirement` and `behaviour-changed`.

## Rules

- Write "None found." under a section with nothing in it. Never omit a section.
- When nothing is required, the bottom line says so and names the most notable item from
  any other section.
- Order items within a section by consequence, most disruptive first.
- A deprecation and its removal within the same range are one Required item naming both
  versions.
- An item whose answer to "Affects the usage" is yes or unknown never goes under
  "Checked, not affecting the usage". A change that breaks something the usage's tests
  assert is Required, of kind `behaviour-changed`, because the test needs changing.
  Something only observed (a dashboard, a log someone reads) goes under "Behaviour to know
  about".
- Never introduce a bare `#123` or `@user`. Write `owner/repo#123`, which GitHub links
  correctly from any repo, or a full URL, and put handles in backticks. Posted on a pull
  request in another repo, a bare reference links to that repo's own issue and a bare
  handle notifies the person.
- When posting on GitHub, put every upstream issue or pull request reference, including
  full URLs to them, in a code span. GitHub records a "mentioned this" event on the
  upstream issue for each reference posted, so a report posted as is would leave a trail of
  backlinks across upstream projects.
- A GitHub comment is capped at 65,536 characters. When posting, shorten "Checked, not
  affecting the usage" first and link to the full report, rather than truncating any required item.
