# Renders each prototype state at 2x into screenshots/. Run from this folder:
#   python3 shoot.py            (dark + light)
import asyncio, os, sys
from playwright.async_api import async_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
STATES = ["browse", "skills", "teach", "assistant", "settings"]
THEMES = sys.argv[1:] or ["dark", "light"]

async def main():
    os.makedirs(os.path.join(HERE, "screenshots"), exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch()
        ctx = await b.new_context(viewport={"width": 1440, "height": 900}, device_scale_factor=2)
        page = await ctx.new_page()
        await page.goto("file://" + os.path.join(HERE, "index.html"))
        await page.wait_for_timeout(300)
        for theme in THEMES:
            for s in STATES:
                await page.evaluate(f"location.hash = '{s}' + ({'1' if theme == 'light' else '0'} ? '+light' : '')")
                await page.wait_for_timeout(350)
                out = os.path.join(HERE, "screenshots", f"{s}-{theme}.png")
                await page.locator("#window").screenshot(path=out, animations="disabled")
                print("wrote", os.path.relpath(out, HERE))
        await b.close()

asyncio.run(main())
