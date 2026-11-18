import {mkdtemp,writeFile,rm,rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
// The dispatcher key is generated in memory, sent through temporary restricted
// files, installed in Supabase secrets/Vault, then the temporary files are removed.
// It is never a command-line argument, source file, or printed output.
const project='xnbqhzawxnjflhoskkds',secret=randomBytes(32).toString('hex'),directory=await mkdtemp(join(tmpdir(),'montme-dispatch-'));
const envFile=join(directory,'secrets.env'),sqlFile=join(directory,'vault.sql');
function cli(args){return new Promise((resolve,reject)=>{const child=spawn(process.execPath,[join(dirname(process.execPath),'node_modules/npm/bin/npx-cli.js'),'--yes','supabase',...args],{stdio:['ignore','pipe','pipe'],windowsHide:true});let output='';child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);child.on('error',reject);child.on('close',code=>{process.stdout.write(output.replaceAll(secret,'[redacted]'));code===0?resolve():reject(Error('Supabase setup command failed.'));});});}
try{
 await writeFile(envFile,`MONTME_DISPATCH_SECRET=${secret}\n`,{mode:0o600});
 await writeFile(sqlFile,`do $$declare existing uuid;begin select id into existing from vault.secrets where name='montme_dispatch_secret' limit 1;if existing is null then perform vault.create_secret('${secret}','montme_dispatch_secret');else perform vault.update_secret(existing,'${secret}');end if;end$$;`,{mode:0o600});
 await cli(['secrets','set','--remote='+project,'--env-file',envFile,'--yes']);
 await cli(['db','query','--remote='+project,'--file',sqlFile,'--yes']);
 console.log('Notification scheduler credential installed in Supabase secrets and Vault.');
}finally{await rm(envFile,{force:true});await rm(sqlFile,{force:true});await rmdir(directory).catch(()=>{});}
