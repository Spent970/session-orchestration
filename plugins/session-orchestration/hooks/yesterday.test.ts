import { expect, mock, test } from 'claude-code/testing'

import { BUILTIN_KEYS, briefLine, briefRows, isLoose, parseBrief, stepDay } from './register'

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 160, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } as const
const NOW = Date.UTC(2026, 9, 22, 7, 0) // a Thursday
const AT = Date.UTC(2026, 9, 21, 10) / 1000
// A brief as session-status --yesterday --json prints it: each item its kind, task key, people, source, time, text.
const BRIEF = (since: string, how: string, more: object = {}) => JSON.stringify({
  since, from: AT, how, notes: [], template: '', failed: [],
  tasks: { 'PROJ-1': { status: 'In Review', title: 'Fix it' } },
  items: [
    { kind: 'worked', key: '"probe"', people: [], source: 'session', at: AT - 3600, text: 'session "probe" (09:00–09:00): Probe done.' },
    { kind: 'worked', key: 'PROJ-1', people: [], source: 'commit', at: AT, text: '2 commits pushed to PROJ-1 in app — last: fix the retry' },
    { kind: 'moved', key: 'PROJ-1', people: [], source: 'pr', at: AT + 60, text: 'app#292 merged' },
    { kind: 'moved', key: 'PROJ-1', people: [], source: 'jira', at: AT + 120, text: 'Jira: Code Review → Ready for Test' },
    { kind: 'discussed', key: 'PROJ-1', people: ['Ann Lee'], source: 'teams', at: AT + 180, text: 'the retry limit' },
    { kind: 'todo', key: 'PROJ-2', people: [], source: 'jira', at: AT + 240, text: 'In Development, no session' },
    { kind: 'asked', key: 'OPS-7', people: ['Bo'], source: 'jira', at: AT + 300, text: 'a staging database' },
    { kind: 'new', key: '', people: ['Di'], source: 'teams', at: AT + 360, text: 'can you look at the build?' },
  ],
  ...more,
})

test('parseBrief: each item\'s data fields, the tasks, the template, failures; a bad field is blank, text that is no brief is other', () => {
  const r = parseBrief(BRIEF('2026-10-21', 'picked', { failed: ['chats: signed out'], template: 'Yesterday I <did>.' }))
  expect([r.since, r.how, r.template, r.failed, r.other]).toEqual(['2026-10-21', 'picked', 'Yesterday I <did>.', ['chats: signed out'], []])
  expect(r.tasks).toEqual({ 'PROJ-1': { status: 'In Review', title: 'Fix it' } })
  expect(r.items.map(i => `${i.kind} ${i.source} ${i.key}`)).toEqual([
    'worked session "probe"', 'worked commit PROJ-1', 'moved pr PROJ-1', 'moved jira PROJ-1', 'discussed teams PROJ-1', 'todo jira PROJ-2', 'asked jira OPS-7', 'new teams ',
  ])
  expect(r.items[4]).toEqual({ kind: 'discussed', key: 'PROJ-1', people: ['Ann Lee'], source: 'teams', at: AT + 180, text: 'the retry limit' })
  expect(parseBrief('{"since":"2026-10-21","items":[{"kind":"moved","people":"x","at":"1"}]}').items).toEqual([{ kind: 'moved', key: '', people: [], source: '', at: 0, text: '' }])
  expect(parseBrief('usage: oops\n').other).toEqual(['usage: oops'])
  expect(parseBrief('').other).toEqual([])
})

test('briefRows: a row per task, the latest first; briefLine: sessions as a count, commits without their last subject, people the text doesn\'t name', () => {
  const { items } = parseBrief(BRIEF('2026-10-21', 'picked'))
  expect(briefRows(items.filter(i => i.kind === 'worked')).map(r => [r[0]?.key, briefLine(r)])).toEqual([['PROJ-1', '2 commits pushed to PROJ-1 in app'], ['"probe"', '1 session']])
  expect(briefLine(items.filter(i => i.kind === 'moved'))).toBe('app#292 merged; Jira: Code Review → Ready for Test')
  // Of a source's moves only the latest: where it stands now.
  expect(briefLine([{ kind: 'moved', key: 'PROJ-1', people: [], source: 'jira', at: 1, text: 'Jira: New → In Review' }, ...items.filter(i => i.kind === 'moved')])).toBe('app#292 merged; Jira: Code Review → Ready for Test')
  expect(briefRows(items.filter(i => i.kind === 'worked')).map(isLoose)).toEqual([false, true])
  expect(briefLine(items.filter(i => i.kind === 'asked'))).toBe('a staging database (Bo)')
  expect(briefLine([{ kind: 'waiting', key: 'PROJ-3', people: ['Cy'], source: 'pr', at: 1, text: 'review by Cy' }])).toBe('review by Cy')
})

test('stepDay skips the weekend both ways; y, b, n and s are the pane\'s own keys', () => {
  expect(stepDay('2026-10-19', -1)).toBe('2026-10-16')
  expect(stepDay('2026-10-16', 1)).toBe('2026-10-19')
  expect(stepDay('2026-10-21', -1)).toBe('2026-10-20')
  expect(['y', 'b', 'n', 's'].every(k => BUILTIN_KEYS[k])).toBe(true)
})

test('y opens the brief on the last working day: a section per kind, a row per task that opens to its list; s lists every task; b and n step the day', async ($, on) => {
  mock.clock(on, { now: NOW })
  const runs: string[][] = []
  on('process.run', async (_, e) => {
    const args = e.argv.slice(2)
    runs.push(e.argv.slice(1))
    const stdout = args[0] === '--yesterday' ? BRIEF(args[2] ?? '2026-10-21', args[2] ? 'picked' : 'last working day') : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  const reads = () => runs.filter(r => r[1] === '--yesterday').map(r => r.slice(1))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'yesterday' })
  expect(reads()).toEqual([['--yesterday', '--json']])
  expect(await ui.find({ type: 'Text', text: /Since 2026-10-21 Wed \(last working day\)/ })).toBeDefined()
  for (const title of ['MOVED', 'WAITS ON YOU', 'YOU WAIT ON', 'NEW FOR YOU', 'WORKED ON'])
    expect(await ui.find({ type: 'Text', text: new RegExp(`^${title}$`) })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /PROJ-1 Fix it — app#292 merged; Jira: Code Review → Ready for Test/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /PROJ-2 — In Development, no session/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /OPS-7 — a staging database \(Bo\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^can you look at the build\? \(Di\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /PROJ-1 Fix it — 2 commits pushed to PROJ-1 in app$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /1 session on no task/ })).toBeDefined()
  // A task's own list is a press away: every item of it, with its source and people; discussed ones only there.
  expect(await ui.find({ type: 'Text', text: /the retry limit/ })).toBeUndefined()
  await ui.press({ key: 'yd-Moved-PROJ-1' })
  expect(await ui.find({ type: 'Text', text: /teams the retry limit \(Ann Lee\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /commit 2 commits pushed to PROJ-1 in app — last: fix the retry/ })).toBeDefined()
  await ui.press({ key: 'yd-Moved-PROJ-1' })
  expect(await ui.find({ type: 'Text', text: /the retry limit/ })).toBeUndefined()
  // s: the list of every task instead of the brief, and back.
  await ui.press({ key: 'yd-list' })
  expect(await ui.find({ type: 'Text', text: /^TASKS$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^MOVED$/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /PROJ-1 In Review Fix it/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /session session "probe" \(09:00–09:00\): Probe done\./ })).toBeDefined()
  await ui.press({ key: 'yd-list' })
  expect(await ui.find({ type: 'Text', text: /^MOVED$/ })).toBeDefined()
  expect(await ui.find({ type: 'Button', key: 'yd-later' })).toBeUndefined()
  await ui.press({ key: 'yd-earlier' })
  expect(reads().at(-1)).toEqual(['--yesterday', '--json', '2026-10-20'])
  expect(await ui.find({ type: 'Text', text: /Since 2026-10-20 Tue \(picked\)/ })).toBeDefined()
  await ui.press({ key: 'yd-later' })
  expect(reads().at(-1)).toEqual(['--yesterday', '--json', '2026-10-21'])
  // On to today: back to the last working day.
  await ui.press({ key: 'yd-later' })
  expect(reads().at(-1)).toEqual(['--yesterday', '--json'])
  expect(await ui.find({ type: 'Button', key: 'yd-later' })).toBeUndefined()
  // No template in the brief: no standup is written.
  expect(runs.some(r => r[0]?.endsWith('/standup-summary'))).toBe(false)
  // Off again: the task board is back.
  await ui.press({ key: 'yesterday' })
  expect(await ui.find({ type: 'Text', text: /Since / })).toBeUndefined()
  await ui.unmount()
})

test('a brief with a template: the standup is written from the brief on stdin and shown on top of it; a failed one says why and the brief stays', async ($, on) => {
  mock.clock(on, { now: NOW })
  const stdins: string[] = []
  let fail = false
  on('process.run', async (_, e) => {
    const summary = String(e.argv[1]).endsWith('/standup-summary')
    if (summary) stdins.push(e.init?.stdin ?? '')
    const stdout = summary ? (fail ? 'model call failed: rate limited' : 'Yesterday I worked on the fix.\n')
      : e.argv[2] === '--yesterday' ? BRIEF('2026-10-21', 'last working day', { template: 'Yesterday I worked on <tasks>.' }) : ''
    return { value: { exitCode: summary && fail ? 1 : 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'yesterday' })
  // The model's input is the data: the template and the items.
  expect(stdins).toHaveLength(1)
  expect(parseBrief(stdins[0] ?? '').template).toBe('Yesterday I worked on <tasks>.')
  expect(parseBrief(stdins[0] ?? '').items).toHaveLength(8)
  expect(await ui.find({ type: 'Text', text: /^Yesterday I worked on the fix\.$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^MOVED$/ })).toBeDefined()
  // The list keeps it on top; a refresh writes it from the new reading.
  await ui.press({ key: 'yd-list' })
  expect(await ui.find({ type: 'Text', text: /^Yesterday I worked on the fix\.$/ })).toBeDefined()
  await ui.press({ key: 'refresh' })
  expect(stdins).toHaveLength(2)
  fail = true
  await ui.press({ key: 'refresh' })
  expect(await ui.find({ type: 'Text', text: /Standup not written \(model call failed: rate limited\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^TASKS$/ })).toBeDefined()
  await ui.unmount()
})
