(() => {
  const game = new globalThis.BlitzGame();
  const canvas = document.getElementById('game-canvas');
  const context = canvas.getContext('2d');
  const palette = [
    '#000000', '#ffffff', '#b33326', '#8cd9d9',
    '#a640b3', '#59d933', '#3333bf', '#d9d959',
    '#b36626', '#e69959', '#e68080', '#bff2f2',
    '#d999d9', '#a6eb8c', '#8ca6eb', '#f2f2a6'
  ];
  const sound = {
    engine: new Audio(`data:audio/wav;base64,${globalThis.AudioData.engine}`),
    hit: new Audio(`data:audio/wav;base64,${globalThis.AudioData.hit}`),
    crash: new Audio(`data:audio/wav;base64,${globalThis.AudioData.crash}`)
  };
  sound.engine.loop = true;
  sound.engine.volume = 0.4;
  sound.hit.volume = 0.75;
  sound.crash.volume = 0.9;
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  let audioContext = null;
  let enginePlaying = false;
  let muted = false;
  let audioErrorReported = false;
  let timer = null;

  function showStorageError(error) {
    console.warn('Blitz could not access local storage.', error);
  }

  try {
    const storedBest = Number.parseInt(localStorage.getItem('blitz-best-score') ?? '0', 10);
    if (Number.isFinite(storedBest) && storedBest > 0) game.setBestScore(storedBest);
  } catch (error) {
    showStorageError(error);
  }

  function showAudioError(error) {
    if (!audioErrorReported) {
      console.warn('Blitz audio is unavailable.', error);
      audioErrorReported = true;
    }
  }

  for (const clip of Object.values(sound)) {
    clip.addEventListener('error', () => showAudioError(new Error('Unable to load an embedded WAV recording.')));
  }

  function playClip(clip) {
    if (muted) return;
    clip.currentTime = 0;
    const playback = clip.play();
    if (playback && typeof playback.catch === 'function') {
      playback.catch((error) => {
        if (clip === sound.engine) enginePlaying = false;
        showAudioError(error);
      });
    }
  }

  let engineBuffer = null;
  let engineSource = null;
  let engineGain = null;

  function loadEngineBuffer() {
    if (engineBuffer || !audioContext) return;
    const bytes = Uint8Array.from(atob(globalThis.AudioData.engine), (c) => c.charCodeAt(0));
    audioContext.decodeAudioData(bytes.buffer.slice(0), (buffer) => {
      engineBuffer = buffer;
      if (enginePlaying && !engineSource) startEngineBuffer();
    }, showAudioError);
  }

  // A buffer source loops gaplessly; looping an <audio> element leaves a gap on mobile that slows the cadence.
  function startEngineBuffer() {
    engineGain = audioContext.createGain();
    engineGain.gain.value = 0.4;
    engineGain.connect(audioContext.destination);
    engineSource = audioContext.createBufferSource();
    engineSource.buffer = engineBuffer;
    engineSource.loop = true;
    engineSource.connect(engineGain);
    engineSource.start();
  }

  function stopEngineBuffer() {
    if (!engineSource) return;
    try { engineSource.stop(); } catch (error) { /* already stopped */ }
    engineSource.disconnect();
    engineSource = null;
  }

  function startEngine() {
    if (muted) return;
    if (audioContext && engineBuffer) {
      if (!engineSource) startEngineBuffer();
    } else if (!audioContext) {
      playClip(sound.engine);
    }
  }

  function resumeAudio() {
    if (!AudioContext) return;
    try {
      if (!audioContext) audioContext = new AudioContext();
      if (audioContext.state === 'suspended') {
        audioContext.resume().catch(showAudioError);
      }
      loadEngineBuffer();
    } catch (error) {
      showAudioError(error);
    }
  }

  function playLandingChime() {
    if (muted || !audioContext) return;
    try {
      const oscillator = audioContext.createOscillator();
      const gain = audioContext.createGain();
      const now = audioContext.currentTime;
      oscillator.type = 'square';
      oscillator.frequency.setValueAtTime(554.37, now);
      gain.gain.setValueAtTime(0.35, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.4);
      oscillator.connect(gain);
      gain.connect(audioContext.destination);
      oscillator.start(now);
      oscillator.stop(now + 0.4);
    } catch (error) {
      showAudioError(error);
    }
  }

  function syncAudio(previousState, previousScore) {
    const shouldRunEngine = game.state === 'playing' && !muted;
    if (shouldRunEngine && !enginePlaying) {
      enginePlaying = true;
      startEngine();
    } else if (!shouldRunEngine && enginePlaying) {
      sound.engine.pause();
      sound.engine.currentTime = 0;
      stopEngineBuffer();
      enginePlaying = false;
    }

    if (previousState !== null && previousState !== 'crashing' && game.state === 'crashing') {
      canvas.classList.remove('shake');
      void canvas.offsetWidth;
      canvas.classList.add('shake');
    }

    if (muted) return;
    if (previousScore !== null && game.getScore() > previousScore) playClip(sound.hit);
    if (previousState !== null && previousState !== 'crashing' && game.state === 'crashing') playClip(sound.crash);
    if (previousState !== null && previousState !== 'landing' && game.state === 'landing') playLandingChime();
  }

  function render() {
    const screen = game.getScreen();
    const colors = game.getColors();
    const cellWidth = canvas.width / 22;
    const cellHeight = canvas.height / 23;
    const pixelWidth = cellWidth / 8;
    const pixelHeight = cellHeight / 8;
    const inRomMode = game.state === 'title' || game.state === 'gameOver';
    context.imageSmoothingEnabled = false;
    context.fillStyle = palette[game.bgColor % palette.length];
    context.fillRect(0, 0, canvas.width, canvas.height);

    for (let row = 0; row < 23; row++) {
      for (let col = 0; col < 22; col++) {
        const index = row * 22 + col;
        const rawCode = screen[index];
        const code = rawCode & 0x7f;
        const reverse = (rawCode & 0x80) !== 0;
        const x = col * cellWidth;
        const y = row * cellHeight;
        const foreground = palette[colors[index] % palette.length];
        let glyph;

        if (reverse) {
          context.fillStyle = foreground;
          context.fillRect(x, y, cellWidth, cellHeight);
        }

        if (inRomMode || row === 0 || code >= 32) {
          glyph = globalThis.FontData.romBytes;
        } else {
          glyph = globalThis.FontData.customSprites;
        }
        if (!inRomMode && row > 0 && code === 32) continue;

        const glyphOffset = code * 8;
        for (let glyphRow = 0; glyphRow < 8; glyphRow++) {
          const bits = glyph[glyphOffset + glyphRow] ?? 0;
          for (let glyphCol = 0; glyphCol < 8; glyphCol++) {
            if ((bits & (0x80 >> glyphCol)) === 0) continue;
            context.fillStyle = reverse ? palette[game.bgColor % palette.length] : foreground;
            context.fillRect(
              x + glyphCol * pixelWidth,
              y + glyphRow * pixelHeight,
              pixelWidth,
              pixelHeight
            );
          }
        }
      }
    }
  }

  function updateReadouts() {}

  function saveBestScore() {
    try {
      localStorage.setItem('blitz-best-score', String(game.getBestScore()));
    } catch (error) {
      showStorageError(error);
    }
  }

  function tick() {
    const previousState = game.state;
    const previousScore = game.getScore();
    game.update();
    syncAudio(previousState, previousScore);
    if (game.state === 'gameOver' && previousState !== 'gameOver') saveBestScore();
    render();
    updateReadouts();
  }

  function resetTimer() {
    if (timer !== null) clearInterval(timer);
    timer = setInterval(tick, game.getSpeedInterval() * 1000);
  }

  function fire() {
    const previousState = game.state;
    const previousScore = game.getScore();
    if (!muted) resumeAudio();
    game.handleFire();
    syncAudio(previousState, previousScore);
    render();
    updateReadouts();
  }

  function toggleSound() {
    muted = !muted;
    if (!muted) {
      resumeAudio();
      syncAudio(null, null);
    } else {
      syncAudio(null, null);
    }
    updateReadouts();
  }

  function toggleDisplay() {
    game.monochromeMode = !game.monochromeMode;
    if (game.state === 'title') game.showTitleScreen();
    else if (game.state === 'playing') game.updateHUD();
    else if (game.state === 'gameOver') game.triggerGameOver();
    render();
    updateReadouts();
  }

  function changeSpeed(direction) {
    if (direction > 0) game.makeFaster();
    else game.makeSlower();
    resetTimer();
    updateReadouts();
  }

  window.addEventListener('keydown', (event) => {
    if ([' ', 'Enter', 'ArrowDown', 'F1'].includes(event.key)) {
      event.preventDefault();
      fire();
    } else if (event.key === 'Escape') {
      game.showTitleScreen();
      render();
      updateReadouts();
    } else if (event.key.toLowerCase() === 'm') {
      toggleDisplay();
    } else if (event.key === '+' || event.key === '=') {
      changeSpeed(1);
    } else if (event.key === '-') {
      changeSpeed(-1);
    }
  });

  canvas.addEventListener('pointerdown', fire);

  render();
  updateReadouts();
  resetTimer();
})();
