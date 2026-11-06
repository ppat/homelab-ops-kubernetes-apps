# Report format

The report is written to a file in this shape. Every section is self-contained, so a caller
can post a subset of sections (for example on a Renovate pull request) and each still reads
on its own. Keep section titles and the item layout stable, since callers select by them.

```markdown
## <deployable>: <FROM> → <TO>

<Bottom line. One sentence giving how many required changes, deprecations and adoption
candidates there are, and the single most important item. "No required changes found" only when
Coverage shows the range was actually read.>

### Required changes

1. **<title naming the exact key, flag or resource>** (<kind>, <version>)
   - Change: <old form → new form, precisely>
   - Affects us: <yes | no | unknown>. <evidence: file path and key, or what would settle it>
   - Action: <what to change, where>
   - Source: <link, or the file and tag read directly when the evidence is source you checked>

   > <verbatim upstream instruction, only when its wording is the instruction>

### Deprecations to plan for

<same item layout. Kind is deprecated, and the version line gives the announced removal
version when upstream states one>

### Behaviour to know about

- **<what changes>** (<version>). <what someone operating it will notice, and why no
  configuration change is needed>. <link>

### Worth adopting

<same item layout. "Affects us" becomes "Fits us", explaining what it would improve for
our use. "None found." is better than a weak item>

### Checked, not affecting us

- <change> (<version>). <why it does not touch our configuration>

### Coverage

| Source | Range | Result |
| --- | --- | --- |
| <e.g. chart releases, owner/repo, prefix> | <versions> | <n read, n missing, n thin> |

Not checked: <every source not read and every config surface not seen, e.g. production
cluster patches when the clusters repo was not available>
```

Kinds for required items: `breaking`, `removed`, `renamed`, `default-changed`,
`new-requirement`, `behaviour-changed`.

## Rules

- Use "None found." under a section with nothing in it. Never omit the section.
- When nothing is required, the bottom line says so and names the most notable item from
  any other section.
- Order items within a section by consequence, most disruptive first.
- A deprecation and its removal inside the same range are one Required item naming both
  versions.
- Never introduce a bare `#123` or `@user`. Write `owner/repo#123` (which GitHub links
  correctly from any repo) or a full URL, and put handles in backticks. Posted on a pull
  request here, a bare reference links to this repo's own issue and a bare handle notifies
  the person.
- An item whose "affects us" answer is yes or unknown never goes under "Checked, not
  affecting us". Something we observe without configuring it (a suite assertion, a
  dashboard) goes under "Behaviour to know about", and the bottom line names it.
- A GitHub comment is capped at 65,536 characters. When posting, shorten "Checked, not
  affecting us" first and link to the full report rather than truncating any required
  item.
