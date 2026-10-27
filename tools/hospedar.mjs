/* Sobe o servidor, abre o túnel do Cloudflare e mostra o endereço.
 *
 * Uso:  npm run hospedar          servidor + túnel
 *       npm run iniciar           servidor + túnel + app de mesa (os lançadores)
 *
 * Enquanto a janela ficar aberta, a sala está no ar. Ctrl+C encerra tudo
 * junto — o endereço morre com eles, e o próximo `hospedar` gera outro. É de
 * propósito: nada fica exposto depois. Com o app, fechar a janela dele também
 * encerra tudo, pelo mesmo motivo.
 *
 * Sem túnel não há sala: o link público é o produto. Cair para localhost em
 * silêncio deixava a pessoa achando que estava no ar quando ninguém de fora
 * conseguia entrar.
 */

import { spawn, fork } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';
import net from 'node:net';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORTA_INICIAL = Number(process.env.PORT) || 3000;
const COM_APP = process.argv.includes('--app');
const linha = '─'.repeat(60);

let servidor = null;
let tunel = null;
let app = null;
let encerrando = false;

/* ================= servidor ================= */

function portaLivre(porta) {
  return new Promise(resolve => {
    const s = net.createServer();
    s.once('error', () => resolve(false));
    s.once('listening', () => s.close(() => resolve(true)));
    s.listen(porta, '127.0.0.1');
  });
}

async function acharPorta(inicial) {
  for (let p = inicial; p < inicial + 20; p++) if (await portaLivre(p)) return p;
  return inicial;
}

function esperarServidor(porta, tentativas = 60) {
  return new Promise((resolve, reject) => {
    const tentar = n => {
      const c = net.connect(porta, '127.0.0.1');
      c.once('connect', () => { c.end(); resolve(); });
      c.once('error', () => {
        c.destroy();
        if (n <= 0) return reject(new Error('o servidor não respondeu a tempo'));
        setTimeout(() => tentar(n - 1), 250);
      });
    };
    tentar(tentativas);
  });
}

async function subirServidor() {
  const porta = await acharPorta(PORTA_INICIAL);
  servidor = fork(path.join(RAIZ, 'server', 'index.js'), [], {
    // Antes de o cloudflared responder, o cliente precisa saber que localhost
    // ainda não é o convite certo. Sem esse estado, um clique rápido copiaria
    // um endereço que só funciona nesta máquina.
    env: { ...process.env, PORT: String(porta), TUNEL_PUBLICO: '1' },
    stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  servidor.stdout?.on('data', d => process.stdout.write(String(d)));
  servidor.stderr?.on('data', d => process.stderr.write(String(d)));
  servidor.on('exit', codigo => {
    servidor = null;
    if (!encerrando) {
      console.error(`\n  O servidor encerrou (código ${codigo}). Encerrando tudo.\n`);
      encerrar(1);
    }
  });
  await esperarServidor(porta);
  return porta;
}

/* ================= túnel ================= */

function subirTunel(porta) {
  return new Promise(resolve => {
    let respondido = false;
    const responder = v => { if (!respondido) { respondido = true; resolve(v); } };

    // a porta é um inteiro validado por acharPorta, então não há interpolação
    // perigosa aqui; o resto do comando é literal
    tunel = spawn('cloudflared', ['tunnel', '--url', `http://localhost:${porta}`]);

    const procurar = texto => {
      const m = String(texto).match(/https:\/\/[-\w.]+\.trycloudflare\.com/);
      if (m) responder({ url: m[0] });
    };
    tunel.stdout?.on('data', procurar);
    tunel.stderr?.on('data', procurar);

    tunel.on('error', e => responder({
      erro: e.code === 'ENOENT'
        ? 'cloudflared não encontrado. Instale com: sudo pacman -S cloudflared'
        : e.message,
    }));
    tunel.on('exit', () => { tunel = null; if (!encerrando) console.error('  (o túnel caiu)'); });

    setTimeout(() => responder({ erro: 'o túnel demorou demais para responder' }), 40000);
  });
}

/* ================= app de mesa ================= */

function abrirApp(porta) {
  // Fora do Electron, `require('electron')` devolve o caminho do executável.
  const executavel = createRequire(import.meta.url)('electron');
  // A porta vai explícita: acharPorta pode ter pulado a 3000, e o app só não
  // sobe servidor próprio quando encontra este já ocupando a porta dele.
  const env = { ...process.env, PORT: String(porta) };
  // Terminal aberto de dentro de outro app Electron (o do VS Code, por
  // exemplo) herda esta variável, e com ela o Electron sobe como Node puro:
  // `app` vem undefined e o main.cjs morre na primeira linha.
  delete env.ELECTRON_RUN_AS_NODE;
  app = spawn(executavel, [RAIZ], { cwd: RAIZ, env, stdio: 'inherit' });
  app.on('error', e => {
    app = null;
    console.error(`\n  Não consegui abrir o app de mesa: ${e.message}\n`);
    encerrar(1);
  });
  app.on('exit', codigo => {
    app = null;
    if (!encerrando) encerrar(codigo ?? 0);
  });
}

/* ================= encerramento ================= */

function encerrar(codigo = 0) {
  if (encerrando) return;
  encerrando = true;
  console.log('\n  Encerrando…');
  try { app?.kill(); } catch {}
  try { tunel?.kill(); } catch {}
  try { servidor?.kill(); } catch {}
  setTimeout(() => process.exit(codigo), 500);
}

process.on('SIGINT', () => encerrar(0));
process.on('SIGTERM', () => encerrar(0));

/* ================= principal ================= */

console.log(`\n${linha}\n  PeekIn — hospedando\n${linha}\n`);

console.log('  Subindo o servidor…');
const porta = await subirServidor();
console.log(`  Servidor no ar em http://localhost:${porta}\n`);

console.log('  Abrindo o túnel público…');
const pedidoTunel = subirTunel(porta);

// O app abre sem esperar o túnel, que leva alguns segundos: até o endereço
// chegar, o "Copiar link" espera em vez de copiar localhost (TUNEL_PUBLICO).
if (COM_APP) {
  console.log('  Abrindo o app de mesa…');
  abrirApp(porta);
}

const t = await pedidoTunel;

if (t.erro) {
  console.error(`\n  Sem link público: ${t.erro}`);
  console.error('  A sala não sobe sem o túnel. Encerrando.\n');
  encerrar(1);
} else {
  // O servidor entrega esse dado ao botão "Copiar link". A janela local pode
  // continuar em localhost, mas o convite tem de levar quem recebe ao túnel.
  servidor?.send?.({ tipo: 'url-publica', url: t.url });
  console.log(`\n${linha}`);
  console.log(`  Endereço da sala:  ${t.url}`);
  console.log(`${linha}\n`);
  console.log('  Mande esse link pra quem vai assistir.\n');
  console.log(COM_APP
    ? '  Deixe esta janela aberta. Ctrl+C aqui, ou fechar o app, encerra tudo.\n'
    : '  Deixe esta janela aberta. Ctrl+C encerra o servidor e o túnel.\n');
}
