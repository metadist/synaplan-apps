#!/usr/bin/env node
/**
 * Stamp manual release signing into the iOS app target.
 *
 * Passing CODE_SIGN_IDENTITY and PROVISIONING_PROFILE_SPECIFIER on the
 * xcodebuild command line applies them to every target in the build graph,
 * including the Swift package targets, which reject provisioning profiles and
 * abort the archive. Writing them into the app target's Release configuration
 * keeps them where they belong.
 */

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PBX_PATH = join(ROOT, 'ios/App/App.xcodeproj/project.pbxproj')
const BLOCK_END = '\n\t\t};'
const SETTING_INDENT = '\t\t\t\t'

/** Slice out every XCBuildConfiguration block with its position in the file. */
function buildConfigurations(pbx) {
  const marker = 'isa = XCBuildConfiguration;'
  const blocks = []
  let found = pbx.indexOf(marker)
  while (found !== -1) {
    const brace = pbx.lastIndexOf('{', found)
    const start = pbx.lastIndexOf('\n', brace) + 1
    const end = pbx.indexOf(BLOCK_END, found)
    if (brace === -1 || end === -1) {
      throw new Error('Malformed XCBuildConfiguration block in project.pbxproj')
    }
    blocks.push({ start, end: end + BLOCK_END.length, text: pbx.slice(start, end) })
    found = pbx.indexOf(marker, end)
  }
  return blocks
}

/** Replace a build setting, or add it when the configuration lacks it. */
function upsertSetting(block, key, value) {
  const assignment = `${SETTING_INDENT}${key} = ${value};`
  const existing = new RegExp(`^\\t+${key} = [^;]*;$`, 'm')
  if (existing.test(block)) {
    return block.replace(existing, assignment)
  }
  const opening = block.indexOf('buildSettings = {\n')
  if (opening === -1) {
    throw new Error('XCBuildConfiguration block without buildSettings')
  }
  const cut = opening + 'buildSettings = {\n'.length
  return `${block.slice(0, cut)}${assignment}\n${block.slice(cut)}`
}

/**
 * Return the project file with manual signing applied to the app target's
 * Release configuration. Debug stays untouched so local builds keep using
 * automatic signing.
 */
export function stampReleaseSigning(pbx, { team, identity, profile }) {
  if (!team || !identity || !profile) {
    throw new Error('Signing needs a team, a certificate identity and a profile name')
  }
  // The app target is the only configuration that carries a bundle identifier;
  // the project-level configurations do not.
  const targets = buildConfigurations(pbx).filter(
    (block) =>
      /^\t+name = Release;$/m.test(block.text) &&
      /^\t+PRODUCT_BUNDLE_IDENTIFIER = [^;]*;$/m.test(block.text)
  )
  if (targets.length !== 1) {
    throw new Error(
      `Expected exactly one Release configuration for the app target, found ${targets.length}`
    )
  }
  const [target] = targets
  let block = target.text
  block = upsertSetting(block, 'CODE_SIGN_STYLE', 'Manual')
  block = upsertSetting(block, 'CODE_SIGN_IDENTITY', JSON.stringify(identity))
  block = upsertSetting(block, 'DEVELOPMENT_TEAM', team)
  block = upsertSetting(block, 'PROVISIONING_PROFILE_SPECIFIER', JSON.stringify(profile))
  return pbx.slice(0, target.start) + block + pbx.slice(target.end - BLOCK_END.length)
}

// CLI entry — run directly (not when imported).
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const stamped = stampReleaseSigning(readFileSync(PBX_PATH, 'utf-8'), {
    team: process.env.APPLE_TEAM_ID,
    identity: process.env.IOS_SIGNING_IDENTITY || 'Apple Distribution',
    profile: process.env.IOS_PROFILE_NAME,
  })
  writeFileSync(PBX_PATH, stamped)
  console.log('[ios-signing] stamped manual release signing into the app target')
}
