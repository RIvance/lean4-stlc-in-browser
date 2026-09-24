import { mountPlayground } from '@language-playground/ide';
import '@language-playground/ide/styles.css';
import './style.css';
import { plugin, editor } from './plugin';

const host = document.getElementById('playground');
if (!host) throw new Error('Missing playground container.');
const handle = mountPlayground(host, {
  plugin, editor, title: 'STLC in Lean', documentTitle: 'STLC in Lean',
});
if (import.meta.hot) import.meta.hot.dispose(() => handle.dispose());
