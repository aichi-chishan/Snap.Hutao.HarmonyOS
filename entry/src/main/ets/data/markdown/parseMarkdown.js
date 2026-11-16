import { Marked } from './marked.js';

function escapeHtml(text) {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function isWebLink(href) {
  return /^https?:\/\/[^/?#\s\\]+(?:[/?#][^\s\\]*)?$/i.test(href);
}

function renderLink(href, label, fallback) {
  return isWebLink(href) ? `<a href="${escapeHtml(href)}">${label}</a>` : escapeHtml(fallback);
}

function highlightExtension(color) {
  return {
    name: 'highlight',
    level: 'inline',
    start(source) {
      const index = source.indexOf('==');
      return index >= 0 ? index : undefined;
    },
    tokenizer(source) {
      const match = /^==(?=\S)([^\n]*?\S)==(?!=)/.exec(source);
      if (match) {
        return { type: 'highlight', raw: match[0], tokens: this.lexer.inlineTokens(match[1]) };
      }
    },
    renderer(token) {
      const content = this.parser.parseInline(token.tokens);
      return `<span style="background-color:${color}">${content}</span>`;
    },
  };
}

function createParser(highlightColor) {
  const parser = new Marked();
  const color = /^#[0-9a-f]{6}$/i.test(highlightColor) ? highlightColor : 'transparent';
  parser.use({
    extensions: [highlightExtension(color)],
    renderer: {
      html(token) {
        return escapeHtml(token.text).replace(/\n/g, '<br>');
      },
      text(token) {
        return token.tokens ? this.parser.parseInline(token.tokens) : escapeHtml(token.text);
      },
      link(token) {
        return renderLink(token.href, this.parser.parseInline(token.tokens), token.raw);
      },
      image(token) {
        return renderLink(token.href, escapeHtml(token.text || token.href), token.raw);
      },
      codespan(token) {
        return `<span style="font-family:monospace">${escapeHtml(token.text)}</span>`;
      },
      checkbox(token) {
        return token.checked ? '☑ ' : '☐ ';
      },
      blockquote(token) {
        return this.parser.parse(token.tokens).replace(/<p>/g, '<p>│ ');
      },
      code(token) {
        const text = escapeHtml(token.text).replace(/ /g, '&#160;').replace(/\n/g, '<br>');
        return `<p><span style="font-family:monospace">${text}</span></p>`;
      },
      table(token) {
        const rows = [token.header, ...token.rows];
        return rows.map(row => `<p>${row.map(cell => this.parser.parseInline(cell.tokens)).join(' │ ')}</p>`).join('');
      },
      hr() {
        return '<p>────────</p>';
      },
    },
  });
  return parser;
}

// ArkUI consumes styled text and separate native blocks for content that StyledString cannot represent.
export function parseMarkdown(markdown, highlightColor) {
  const parser = createParser(highlightColor);
  const tokens = parser.lexer(markdown);
  const blocks = [];
  for (const token of tokens) {
    const source = token.raw;
    switch (token.type) {
      case 'space':
      case 'def':
        break;
      case 'code':
        blocks.push({ kind: 'code', source, text: token.text, language: token.lang?.trim() || '' });
        break;
      case 'table': {
        const rows = [token.header, ...token.rows].map(row => row.map(cell => ({
          text: cell.text,
          html: parser.parser([{ type: 'paragraph', tokens: cell.tokens }]),
          alignment: cell.align ?? '',
        })));
        blocks.push({ kind: 'table', source, rows });
        break;
      }
      case 'hr':
        blocks.push({ kind: 'rule', source });
        break;
      case 'blockquote':
        blocks.push({ kind: 'quote', source, html: parser.parser(token.tokens) });
        break;
      default:
        blocks.push({ kind: 'rich', source, html: parser.parser([token]) });
        break;
    }
  }
  return JSON.stringify(blocks);
}
