const board = document.getElementById('knowledge-board')
const status = document.getElementById('canvas-status')
const url = new URL(window.location.href)

// Full-page mode keeps card links in the address bar and opens notes on this site.
const hasCanvas = url.searchParams.has('canvas')
const hasVault = url.searchParams.has('vault')
if (!hasCanvas) url.searchParams.set('canvas', board.dataset.canvas)
if (!hasVault) url.searchParams.set('vault', board.dataset.vault)
history.replaceState(history.state, '', url)

try {
  const renderer = await import(board.dataset.renderer)
  await renderer.mount(board)
  status.hidden = true
} catch (error) {
  status.textContent = `Could not load the knowledge map: ${error.message}. Reload this page to try again.`
  console.error(error)
} finally {
  board.setAttribute('aria-busy', 'false')
}
