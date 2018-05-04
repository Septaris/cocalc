/*
Register the LaTeX file editor

*/

import { Editor } from "./editor.tsx";
import { Actions } from "./actions.ts";

import {register_file_editor} from '../frame-tree/register';

// Load plugin so that codemirror can automatically close latex environments.
import "./codemirror-autoclose-latex";

register_file_editor({
  ext: "tex",
  component: Editor,
  Actions
});
