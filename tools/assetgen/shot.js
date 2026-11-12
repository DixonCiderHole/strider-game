// node shot.js model.glb out.png "camx,camy,camz" "tx,ty,tz" [fov]
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const [glb, out, ...views] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 1400, height: 800 } });
  p.on('console', m => console.log('page:', m.text())); p.on('pageerror', e => console.log('err:', e.message));
  await p.goto('file://' + path.resolve(__dirname, 'viewer.html'));
  const data = fs.readFileSync(glb).toString('base64');
  let i = 0;
  for (const v of views) {
    const [c, t, f] = v.split('|');
    const r = await p.evaluate(async ([d, c, t, f]) => render(d, c.split(',').map(Number), t.split(',').map(Number), { fov: Number(f || 0.8) }), [data, c, t, f]);
    await p.screenshot({ path: out.replace('.png', `_${i++}.png`) });
  }
  await b.close();
})();
