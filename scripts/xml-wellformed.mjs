/*
 * Tiny dependency-free XML well-formedness check for the native manifests
 * (Info.plist, AndroidManifest.xml, PrivacyInfo.xcprivacy). Node core has no XML
 * parser; this is intentionally minimal — it proves tags are balanced + properly
 * nested (the kind of breakage a hand-edit causes), not full DTD/schema validity.
 *
 * Handles: <?xml ?> declarations, <!DOCTYPE ...>, <!-- comments -->,
 * <![CDATA[ ... ]]>, self-closing <tag/>, and quoted attribute values (so a `>`
 * inside an attribute value is not mistaken for a tag end).
 */

/** Throws an Error with a descriptive message if `xml` is not well-formed. */
export function assertWellFormed(xml, label = 'XML') {
  const stack = []
  let i = 0
  const n = xml.length

  while (i < n) {
    const lt = xml.indexOf('<', i)
    if (lt === -1) break
    i = lt

    // Declarations / comments / CDATA / doctype.
    if (xml.startsWith('<?', i)) {
      const end = xml.indexOf('?>', i)
      if (end === -1) throw new Error(`${label}: unterminated <?…?> declaration`)
      i = end + 2
      continue
    }
    if (xml.startsWith('<!--', i)) {
      const end = xml.indexOf('-->', i)
      if (end === -1) throw new Error(`${label}: unterminated comment`)
      i = end + 3
      continue
    }
    if (xml.startsWith('<![CDATA[', i)) {
      const end = xml.indexOf(']]>', i)
      if (end === -1) throw new Error(`${label}: unterminated CDATA`)
      i = end + 3
      continue
    }
    if (xml.startsWith('<!', i)) {
      const end = xml.indexOf('>', i)
      if (end === -1) throw new Error(`${label}: unterminated <!…> declaration`)
      i = end + 1
      continue
    }

    // A real element tag — scan to its closing '>' respecting quotes.
    let j = i + 1
    let quote = null
    while (j < n) {
      const c = xml[j]
      if (quote) {
        if (c === quote) quote = null
      } else if (c === '"' || c === "'") {
        quote = c
      } else if (c === '>') {
        break
      }
      j++
    }
    if (j >= n) throw new Error(`${label}: unterminated tag starting at offset ${i}`)

    const inner = xml.slice(i + 1, j).trim()
    if (inner.startsWith('/')) {
      // Closing tag.
      const name = inner.slice(1).trim().split(/\s/)[0]
      const top = stack.pop()
      if (top !== name) {
        throw new Error(`${label}: mismatched closing tag </${name}> (expected </${top ?? 'EOF'}>)`)
      }
    } else if (inner.endsWith('/')) {
      // Self-closing — no nesting change.
    } else {
      const name = inner.split(/[\s/]/)[0]
      if (name) stack.push(name)
    }
    i = j + 1
  }

  if (stack.length > 0) {
    throw new Error(`${label}: unclosed tag(s): ${stack.join(', ')}`)
  }
  return true
}
