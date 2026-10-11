// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro
//
// Pull Request のチェック (.github/workflows/pr-checks.yml) の補助。結果は GitHub の「Summary」に表で出す。
//   node pr-checks.mjs cases <出力ファイル>        … Pull Request の「確かめること」と「Fixes #12」の誤判定の報告から、確かめる例を集める
//   node pr-checks.mjs expect <結果の JSON>        … 例の結果を表にし、外れがあれば失敗
//   node pr-checks.mjs compare <main の JSON> <Pull Request の JSON>  … 品質テストを比べ、新しく外れた例があれば失敗
// Pull Request の本文・Issue の本文は値として扱うだけ (コマンドとして実行しない)。
import fs from 'node:fs';

const api = process.env.GITHUB_API_URL ?? 'https://api.github.com';
const repo = process.env.GITHUB_REPOSITORY;
const summary = text => fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY ?? '/dev/stdout', text + '\n');
const code = text => '`' + String(text ?? '').replace(/`/g, 'ˋ').replace(/\|/g, '\\|') + '`';
const cell = text => String(text ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ');

async function gh(url) {
  const response = await fetch(`${api}/repos/${repo}${url}`, {
    headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json', 'User-Agent': 'meltype-bot' },
  });
  return response.ok ? response.json() : null;
}

/** Issue フォームの本文の「### 見出し」の値。 */
function formField(body, prefix) {
  for (const part of (body ?? '').split(/^### /m).slice(1)) {
    const newline = part.indexOf('\n');
    if (part.slice(0, newline).trim().startsWith(prefix)) {
      const value = part.slice(newline + 1).trim();
      return value === '_No response_' ? '' : value;
    }
  }
  return '';
}

async function cases(output) {
  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const body = event.pull_request?.body ?? '';
  const list = [];

  // 「## 確かめること」の下の「入力 → 期待」の行
  const section = body.split(/^##\s*確かめること\s*$/m)[1]?.split(/^##\s/m)[0] ?? '';
  for (const line of section.split('\n')) {
    const match = line.replace(/^\s*[-*]\s*/, '').match(/^(.+?)\s*(?:→|->)\s*(.+)$/);
    if (!match || line.trim().startsWith('<!--')) continue;
    list.push({ typed: match[1].replace(/`/g, '').trim(), expected: match[2].replace(/`/g, '').trim(), source: '確かめること' });
  }

  // 「Fixes #12」などで閉じる Issue が誤判定の報告なら、その報告の「打ったもの → 期待した結果」
  for (const [, number] of body.matchAll(/\b(?:fix(?:e[sd])?|close[sd]?|resolve[sd]?)\s+#(\d+)/gi)) {
    const issue = await gh(`/issues/${number}`);
    if (!issue || !issue.labels.some(l => l.name === '誤判定')) continue;
    // 報告の欄がコードの書き方 (`gameover`) で書かれていたら、「確かめること」の行と同じくバッククォートを外す
    const plain = text => text.replace(/^`+|`+$/g, '').trim();
    const typed = plain(formField(issue.body, '打ったもの')), expected = plain(formField(issue.body, '期待した結果'));
    if (/^[\x20-\x7e]+$/.test(typed) && expected) list.push({ typed, expected, source: `#${number}` });
  }

  fs.writeFileSync(output, list.map(c => `${c.typed}\t${c.expected}`).join('\n') + '\n');
  fs.writeFileSync(output + '.sources.json', JSON.stringify(list.map(c => c.source)));
  fs.appendFileSync(process.env.GITHUB_OUTPUT ?? '/dev/null', `count=${list.length}\n`);
  console.log(`確かめる例: ${list.length} 個`);
}

function expect(resultFile) {
  const results = JSON.parse(fs.readFileSync(resultFile, 'utf8'));
  let sources = [];
  try { sources = JSON.parse(fs.readFileSync(resultFile.replace(/\.json$/, '.txt.sources.json'), 'utf8')); } catch { /* 無くてもよい */ }
  const failed = results.filter(r => !r.ok).length;
  summary(`## 報告・確かめることの再現 ${failed === 0 ? '✅' : '❌'}\n`);
  summary('| | 出どころ | 入力 | 期待 | Pull Request の結果 | 比べ方 |\n|---|---|---|---|---|---|');
  results.forEach((r, i) => summary(`| ${r.ok ? '✅' : '❌'} | ${cell(sources[i] ?? '')} | ${code(r.typed)} | ${cell(r.expected)} | ${cell(r.actual)} | ${cell(r.kind)} |`));
  summary('\n<sub>テスト用の変換エンジンなので漢字にはしません。期待に漢字が入っている例は、日本語 / 英語の分かれ方だけを比べます。</sub>');
  if (failed > 0) {
    console.error(`${failed} 個の例が期待どおりになりませんでした`);
    process.exitCode = 1;
  }
}

function compare(baseFile, prFile) {
  const pr = JSON.parse(fs.readFileSync(prFile, 'utf8'));
  let base = null;
  try { base = JSON.parse(fs.readFileSync(baseFile, 'utf8')); } catch { /* main に --eval-json がまだ無い */ }
  const baseCases = new Map((base?.cases ?? []).map(c => [c.key, c]));
  const broken = pr.cases.filter(c => !c.ok && baseCases.get(c.key)?.ok === true);
  const fixed = pr.cases.filter(c => c.ok && baseCases.get(c.key)?.ok === false);
  const added = base ? pr.cases.filter(c => !baseCases.has(c.key)) : [];
  const addedFailing = added.filter(c => !c.ok);
  const rate = r => `${r.pass}/${r.total} (${(r.pass / r.total * 100).toFixed(1)}%)`;

  summary(`## 精度の比較 ${broken.length + addedFailing.length === 0 ? '✅' : '❌'}\n`);
  summary(`| | 品質テスト |\n|---|---|\n| main | ${base ? rate(base) : '(比べられません)'} |\n| Pull Request | ${rate(pr)} |\n`);
  const list = (title, items) => {
    if (items.length === 0) return;
    summary(`### ${title} (${items.length})\n`);
    for (const c of items.slice(0, 50)) summary(`- ${cell(c.detail)}`);
    if (items.length > 50) summary(`- …ほか ${items.length - 50} 個`);
    summary('');
  };
  list('❌ 新しく外れた例', broken);
  list('❌ 新しく足した例で外れたもの', addedFailing);
  list('✅ 直った例', fixed);
  list('➕ 新しく足した例', added.filter(c => c.ok));
  if (broken.length + addedFailing.length > 0) {
    console.error(`新しく外れた例が ${broken.length + addedFailing.length} 個あります`);
    process.exitCode = 1;
  }
}

const [mode, a, b] = process.argv.slice(2);
if (mode === 'cases') await cases(a);
else if (mode === 'expect') expect(a);
else if (mode === 'compare') compare(a, b);
