import { describe, expect, it } from 'vitest'
import en from './locales/en.json'
import si from './locales/si.json'
import sv from './locales/sv.json'

type Tree = { [key: string]: string | Tree }

function flatten(tree: Tree, prefix = ''): Record<string, string> {
  const out: Record<string, string> = {}
  for (const [key, value] of Object.entries(tree)) {
    const path = prefix ? `${prefix}.${key}` : key
    if (typeof value === 'string') out[path] = value
    else Object.assign(out, flatten(value, path))
  }
  return out
}

const placeholders = (text: string) => (text.match(/{{\s*\w+\s*}}/g) ?? []).sort().join(',')

const base = flatten(en as Tree)
const others: Record<string, Record<string, string>> = {
  si: flatten(si as Tree),
  sv: flatten(sv as Tree),
}

describe('translations', () => {
  for (const [code, strings] of Object.entries(others)) {
    it(`${code} has exactly the same keys as English`, () => {
      expect(Object.keys(strings).sort()).toEqual(Object.keys(base).sort())
    })

    it(`${code} has no empty texts`, () => {
      for (const [key, text] of Object.entries(strings)) {
        expect(text.trim().length, `${code}:${key}`).toBeGreaterThan(0)
      }
    })

    it(`${code} keeps the same {{placeholders}} as English`, () => {
      for (const key of Object.keys(base)) {
        expect(placeholders(strings[key]), `${code}:${key}`).toBe(placeholders(base[key]))
      }
    })
  }
})
