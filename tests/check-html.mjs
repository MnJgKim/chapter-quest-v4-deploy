import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const html=await readFile(new URL('../public/index.html',import.meta.url),'utf8');let count=0;
for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){if(/\bsrc=/.test(match[1]))continue;new vm.Script(match[2],{filename:`inline-${++count}`});}
for(const name of ['runtime-config.js','account-activation.js','student-session.js'])new vm.Script(await readFile(new URL('../public/'+name,import.meta.url),'utf8'),{filename:name});
console.log(`PASS: ${count} inline scripts and 3 added scripts parse`);
