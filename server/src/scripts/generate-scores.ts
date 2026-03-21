const fs = require('fs');
const path = require('path');
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// MusicXML 生成模板
function buildXml({ title, composer, timeSig, keyFifths, tempo, measures }) {
  const [beats, beatType] = timeSig.split('/').map(Number);
  const divisions = 4; // 每拍4个单位

  let measuresXml = '';
  for (let i = 0; i < measures.length; i++) {
    const m = measures[i];
    let notesXml = '';
    for (const note of m) {
      const [step, octave, dur, type] = note;
      const isRest = step === 'rest';
      const alter = (!isRest && (step.includes('#') || step.includes('b'))) ? `\n          <alter>${step.endsWith('#') ? 1 : -1}</alter>` : '';
      const cleanStep = step.replace(/[0-9#b]/g, '');
      const pitchOrRest = isRest ? '<rest/>' : `<pitch>
          <step>${cleanStep}</step>${alter}
          <octave>${octave}</octave>
        </pitch>`;
      notesXml += `
      <note>
        ${pitchOrRest}
        <duration>${dur}</duration>
        <voice>1</voice>
        <type>${type}</type>
        <staff>1</staff>
      </note>`;
    }

    const attrs = i === 0 ? `
      <attributes>
        <divisions>${divisions}</divisions>
        <key>
          <fifths>${keyFifths}</fifths>
        </key>
        <time>
          <beats>${beats}</beats>
          <beat-type>${beatType}</beat-type>
        </time>
        <clef>
          <sign>G</sign>
          <line>2</line>
        </clef>
      </attributes>
      <direction placement="above">
        <direction-type>
          <metronome parentheses="no">
            <beat-unit>quarter</beat-unit>
            <per-minute>${tempo}</per-minute>
          </metronome>
        </direction-type>
        <sound tempo="${tempo}"/>
      </direction>` : '';

    measuresXml += `
    <measure number="${i + 1}">${attrs}${notesXml}
    </measure>`;
  }

  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="3.1">
  <work>
    <work-title>${title}</work-title>
  </work>
  <identification>
    <creator type="composer">${composer}</creator>
    <encoding>
      <software>DeepMusic</software>
      <encoding-date>2026-03-21</encoding-date>
    </encoding>
  </identification>
  <part-list>
    <score-part id="P1">
      <part-name>Piano</part-name>
      <score-instrument id="P1-I1">
        <instrument-name>Piano</instrument-name>
      </score-instrument>
      <midi-instrument id="P1-I1">
        <midi-channel>1</midi-channel>
        <midi-program>1</midi-program>
      </midi-instrument>
    </score-part>
  </part-list>
  <part id="P1">${measuresXml}
  </part>
</score-partwise>`;
}

// N = quarter=4, H = half=8, W = whole=16, E = eighth=2, S = sixteenth=1
// [step+alter, octave, duration, type]
const N = (s,o) => [s,o,4,'quarter'];
const H = (s,o) => [s,o,8,'half'];
const W = (s,o) => [s,o,16,'whole'];
const E = (s,o) => [s,o,2,'eighth'];
const S = (s,o) => [s,o,1,'sixteenth'];
const R = (d,t) => ['rest',4,d,t]; // rest

// 30首乐谱数据
const scores = {
  '致爱丽丝 (Für Elise)': {
    timeSig: '3/8', keyFifths: 0, tempo: 72,
    measures: [
      [E('E5',5), E('D#5',5), E('E5',5), E('D#5',5), E('E5',5), E('B4',4)],
      [E('D5',5), E('C5',5), H('A4',4)],
      [R(4,'quarter'), E('C4',4), E('E4',4), E('A4',4)],
      [H('B4',4), R(4,'quarter')],
      [R(4,'quarter'), E('E4',4), E('G#4',4), E('B4',4)],
      [H('C5',5), R(4,'quarter')],
      [R(4,'quarter'), E('E4',4), E('E5',5), E('D#5',5)],
      [E('E5',5), E('D#5',5), E('E5',5), E('D#5',5), E('E5',5), E('B4',4)],
      [E('D5',5), E('C5',5), H('A4',4)],
      [R(4,'quarter'), E('C4',4), E('E4',4), E('A4',4)],
      [H('B4',4), R(4,'quarter')],
      [R(4,'quarter'), E('E4',4), E('C5',5), E('B4',4)],
      [H('A4',4), R(4,'quarter')],
    ]
  },
  '小步舞曲 (Minuet in G)': {
    timeSig: '3/4', keyFifths: 1, tempo: 120,
    measures: [
      [H('D5',5), N('G4',4), N('G4',4)],
      [N('A4',4), N('B4',4), N('A4',4)],
      [N('B4',4), N('C5',5), N('D5',5)],
      [H('G4',4), N('G4',4)],
      [N('E5',5), N('C5',5), N('D5',5)],
      [N('E5',5), N('D5',5), N('C5',5)],
      [N('D5',5), N('B4',4), N('C5',5)],
      [H('A4',4), N('A4',4)],
      [N('B4',4), N('C5',5), N('D5',5)],
      [H('G4',4), N('G4',4)],
      [N('A4',4), N('B4',4), N('C5',5)],
      [H('D5',5), N('G4',4)],
    ]
  },
  '梦幻曲 (Träumerei)': {
    timeSig: '4/4', keyFifths: -1, tempo: 72,
    measures: [
      [E('F5',5), E('E5',5), E('D5',5), E('C5',5), E('D5',5), E('C5',5), E('A4',4), E('B4',4)],
      [W('C5',5)],
      [E('C5',5), E('D5',5), E('E5',5), E('F5',5), E('E5',5), E('D5',5), E('C5',5), E('B4',4)],
      [W('A4',4)],
      [E('A4',4), E('B4',4), E('C5',5), E('D5',5), E('E5',5), E('F5',5), E('G5',5), E('F5',5)],
      [H('E5',5), H('C5',5)],
      [E('D5',5), E('E5',5), E('F5',5), E('E5',5), E('D5',5), E('C5',5), E('B4',4), E('A4',4)],
      [W('B4',4)],
    ]
  },
  '月光奏鸣曲第一乐章': {
    timeSig: '4/4', keyFifths: 4, tempo: 52,
    measures: [
      [E('G#4',4), E('C5',5), E('E5',5), E('G#4',4), E('C5',5), E('E5',5), E('G#4',4), E('C5',5)],
      [E('E5',5), E('G#4',4), E('C5',5), E('E5',5), E('G#4',4), E('C5',5), E('E5',5), E('G#4',4)],
      [E('G#4',4), E('C5',5), E('E5',5), E('G#4',4), E('B4',4), E('E5',5), E('G#4',4), E('B4',4)],
      [E('E5',5), E('G#4',4), E('B4',4), E('E5',5), E('A4',4), E('C5',5), E('E5',5), E('A4',4)],
      [E('A4',4), E('C5',5), E('E5',5), E('A4',4), E('A4',4), E('C5',5), E('E5',5), E('A4',4)],
      [E('G#4',4), E('C5',5), E('E5',5), E('G#4',4), E('C5',5), E('E5',5), E('G#4',4), E('C5',5)],
      [E('F#4',4), E('A4',4), E('E5',5), E('F#4',4), E('A4',4), E('E5',5), E('F#4',4), E('A4',4)],
      [E('G#4',4), E('C5',5), E('E5',5), E('G#4',4), E('C5',5), E('E5',5), E('G#4',4), E('B4',4)],
    ]
  },
  '土耳其进行曲': {
    timeSig: '2/4', keyFifths: 0, tempo: 120,
    measures: [
      [E('B4',4), E('A#4',4), N('B4',4)],
      [E('F#4',4), E('A4',4), N('B4',4)],
      [E('B4',4), E('A#4',4), N('B4',4)],
      [E('F#4',4), E('A4',4), N('B4',4)],
      [E('B4',4), E('C5',5), N('D5',5)],
      [E('E5',5), E('D5',5), N('C5',5)],
      [E('B4',4), E('A#4',4), N('B4',4)],
      [E('F#4',4), E('A4',4), N('B4',4)],
      [N('E5',5), N('D5',5)],
      [N('C5',5), N('B4',4)],
      [N('A4',4), N('G#4',4)],
      [N('A4',4), N('B4',4)],
    ]
  },
  '快乐的农夫': {
    timeSig: '4/4', keyFifths: -1, tempo: 100,
    measures: [
      [N('C4',4), N('E4',4), N('G4',4), N('C5',5)],
      [N('G4',4), N('E4',4), N('C4',4), R(4,'quarter')],
      [N('D4',4), N('F4',4), N('A4',4), N('D5',5)],
      [N('A4',4), N('F4',4), N('D4',4), R(4,'quarter')],
      [N('E4',4), N('G4',4), N('B4',4), N('E5',5)],
      [N('D5',5), N('B4',4), N('G4',4), R(4,'quarter')],
      [N('C5',5), N('B4',4), N('A4',4), N('G4',4)],
      [H('C5',5), H('C4',4)],
    ]
  },
  '卡农': {
    timeSig: '4/4', keyFifths: 2, tempo: 60,
    measures: [
      [N('F#4',4), N('E4',4), N('D4',4), N('C#4',4)],
      [N('B3',3), N('A3',3), N('B3',3), N('C#4',4)],
      [N('D4',4), N('C#4',4), N('B3',3), N('A3',3)],
      [N('G3',3), N('F#3',3), N('G3',3), N('A3',3)],
      [H('F#4',4), H('E4',4)],
      [H('D4',4), H('C#4',4)],
      [H('B3',3), H('A3',3)],
      [H('G3',3), N('F#3',3), N('E3',3)],
    ]
  },
  '悲怆奏鸣曲第二乐章': {
    timeSig: '2/4', keyFifths: -4, tempo: 60,
    measures: [
      [N('Ab4',4), N('Ab4',4)],
      [N('Ab4',4), N('Bb4',4)],
      [N('C5',5), N('Bb4',4)],
      [N('Ab4',4), N('Ab4',4)],
      [N('Ab4',4), N('C5',5)],
      [N('Eb5',5), N('C5',5)],
      [N('Ab4',4), N('Ab4',4)],
      [N('Bb4',4), N('Ab4',4)],
      [N('G4',4), N('Ab4',4)],
      [H('Bb4',4)],
    ]
  },
  '献给爱丽丝': {
    timeSig: '3/8', keyFifths: 0, tempo: 72,
    measures: [
      [E('E5',5), E('D#5',5), E('E5',5), E('D#5',5), E('E5',5), E('B4',4)],
      [E('D5',5), E('C5',5), H('A4',4)],
      [R(4,'quarter'), E('C4',4), E('E4',4), E('A4',4)],
      [H('B4',4), R(4,'quarter')],
      [R(4,'quarter'), E('E4',4), E('G#4',4), E('B4',4)],
      [H('C5',5), R(4,'quarter')],
      [R(4,'quarter'), E('E4',4), E('E5',5), E('D#5',5)],
      [E('E5',5), E('D#5',5), E('E5',5), E('D#5',5), E('E5',5), E('B4',4)],
      [E('D5',5), E('C5',5), H('A4',4)],
      [R(4,'quarter'), E('C4',4), E('E4',4), E('A4',4)],
      [H('B4',4), R(4,'quarter')],
      [R(4,'quarter'), E('E4',4), E('C5',5), E('B4',4)],
      [H('A4',4), R(4,'quarter')],
    ]
  },
  '蓝色多瑙河': {
    timeSig: '3/4', keyFifths: 2, tempo: 120,
    measures: [
      [N('D4',4), N('F#4',4), N('A4',4)],
      [N('A4',4), R(2,'eighth'), N('A4',4)],
      [N('A4',4), N('F#4',4), N('D4',4)],
      [N('D4',4), R(2,'eighth'), N('D4',4)],
      [N('E4',4), N('G4',4), N('B4',4)],
      [N('B4',4), R(2,'eighth'), N('B4',4)],
      [N('A4',4), N('G4',4), N('F#4',4)],
      [N('D4',4), R(2,'eighth'), N('D4',4)],
      [N('D5',5), N('C#5',5), N('B4',4)],
      [N('A4',4), N('G4',4), N('F#4',4)],
    ]
  },
  '小星星变奏曲': {
    timeSig: '2/4', keyFifths: 0, tempo: 100,
    measures: [
      [N('C4',4), N('C4',4)],
      [N('G4',4), N('G4',4)],
      [N('A4',4), N('A4',4)],
      [N('G4',4), R(4,'quarter')],
      [N('F4',4), N('F4',4)],
      [N('E4',4), N('E4',4)],
      [N('D4',4), N('D4',4)],
      [N('C4',4), R(4,'quarter')],
      [E('C4',4), E('D4',4), E('E4',4), E('F4',4)],
      [N('G4',4), R(4,'quarter')],
    ]
  },
  '雨滴前奏曲': {
    timeSig: '4/4', keyFifths: -5, tempo: 56,
    measures: [
      [E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4)],
      [E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4)],
      [N('B4',4), N('C5',5), N('Db5',5), N('B4',4)],
      [E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4)],
      [N('Eb5',5), N('Db5',5), N('C5',5), N('B4',4)],
      [E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4), E('Ab4',4)],
      [N('B4',4), N('C5',5), N('Db5',5), N('Eb5',5)],
      [W('E5',5)],
    ]
  },
  '离别曲': {
    timeSig: '4/4', keyFifths: 3, tempo: 60,
    measures: [
      [N('E4',4), N('G#4',4), N('B4',4), N('E5',5)],
      [N('D#5',5), N('C#5',5), N('B4',4), N('A4',4)],
      [N('G#4',4), N('B4',4), N('E5',5), N('B4',4)],
      [W('C#5',5)],
      [N('B4',4), N('C#5',5), N('D#5',5), N('E5',5)],
      [N('F#5',5), N('E5',5), N('D#5',5), N('C#5',5)],
      [H('B4',4), H('A4',4)],
      [W('G#4',4)],
    ]
  },
  '少女的祈祷': {
    timeSig: '4/4', keyFifths: -3, tempo: 80,
    measures: [
      [N('Eb4',4), N('G4',4), N('Bb4',4), N('Eb5',5)],
      [N('D5',5), N('C5',5), N('Bb4',4), N('Ab4',4)],
      [N('G4',4), N('Ab4',4), N('Bb4',4), N('C5',5)],
      [W('Bb4',4)],
      [N('Eb5',5), N('D5',5), N('C5',5), N('Bb4',4)],
      [N('Ab4',4), N('G4',4), N('F4',4), N('Eb4',4)],
      [H('Ab4',4), H('Bb4',4)],
      [W('Eb5',5)],
    ]
  },
  '军队进行曲': {
    timeSig: '2/4', keyFifths: 2, tempo: 120,
    measures: [
      [N('D4',4), N('D4',4)],
      [N('A4',4), N('F#4',4)],
      [N('A4',4), N('D5',5)],
      [N('D5',5), R(4,'quarter')],
      [N('E5',5), N('C#5',5)],
      [N('E5',5), N('A4',4)],
      [N('D5',5), N('A4',4)],
      [N('F#4',4), R(4,'quarter')],
      [N('D5',5), N('D5',5)],
      [N('C#5',5), N('B4',4)],
    ]
  },
  '春之歌': {
    timeSig: '6/8', keyFifths: 3, tempo: 96,
    measures: [
      [E('E5',5), E('C#5',5), E('A4',4), E('E5',5), E('C#5',5), E('A4',4)],
      [E('F#5',5), E('D5',5), E('B4',4), E('E5',5), E('C#5',5), E('A4',4)],
      [E('E5',5), E('F#5',5), E('E5',5), E('D5',5), E('C#5',5), E('B4',4)],
      [N('A4',4), R(2,'eighth'), N('A4',4), R(2,'eighth')],
      [E('C#5',5), E('B4',4), E('A4',4), E('C#5',5), E('E5',5), E('A5',5)],
      [E('F#5',5), E('E5',5), E('D5',5), E('C#5',5), E('B4',4), E('A4',4)],
      [H('E5',5), H('A4',4)],
    ]
  },
  '蝴蝶': {
    timeSig: '2/4', keyFifths: 3, tempo: 100,
    measures: [
      [E('A4',4), E('C#5',5), E('E5',5), E('C#5',5)],
      [N('A4',4), R(4,'quarter')],
      [E('B4',4), E('D5',5), E('F#5',5), E('D5',5)],
      [N('B4',4), R(4,'quarter')],
      [E('C#5',5), E('E5',5), E('A5',5), E('E5',5)],
      [N('C#5',5), R(4,'quarter')],
      [E('D5',5), E('B4',4), E('F#4',4), E('D4',4)],
      [H('E4',4)],
    ]
  },
  '茉莉花': {
    timeSig: '4/4', keyFifths: -3, tempo: 80,
    measures: [
      [N('Eb4',4), N('Eb4',4), N('G4',4), N('Ab4',4)],
      [N('G4',4), N('Eb4',4), N('G4',4), R(4,'quarter')],
      [N('Ab4',4), N('Ab4',4), N('G4',4), N('Ab4',4)],
      [H('Bb4',4), H('G4',4)],
      [N('Eb5',5), N('Eb5',5), N('D5',5), N('C5',5)],
      [N('Bb4',4), N('Ab4',4), N('G4',4), R(4,'quarter')],
      [N('Ab4',4), N('Bb4',4), N('C5',5), N('Eb5',5)],
      [W('Eb5',5)],
    ]
  },
  '天空之城': {
    timeSig: '4/4', keyFifths: 0, tempo: 72,
    measures: [
      [N('E5',5), N('C5',5), N('G4',4), N('C5',5)],
      [N('G4',4), N('C5',5), N('E5',5), N('D5',5)],
      [N('C5',5), N('A4',4), N('E4',4), N('A4',4)],
      [N('C5',5), N('B4',4), N('A4',4), N('G4',4)],
      [N('E5',5), N('C5',5), N('G4',4), N('C5',5)],
      [N('G4',4), N('C5',5), N('D5',5), N('E5',5)],
      [H('C5',5), H('A4',4)],
      [W('G4',4)],
    ]
  },
  '圣诞快乐，劳伦斯先生': {
    timeSig: '4/4', keyFifths: 0, tempo: 60,
    measures: [
      [N('C4',4), N('E4',4), N('G4',4), N('C5',5)],
      [H('B4',4), H('G4',4)],
      [N('A4',4), N('C5',5), N('E5',5), N('D5',5)],
      [H('C5',5), H('G4',4)],
      [N('C4',4), N('E4',4), N('G4',4), N('E5',5)],
      [H('D5',5), H('B4',4)],
      [N('C5',5), N('A4',4), N('G4',4), N('E4',4)],
      [W('C4',4)],
    ]
  },
  '匈牙利舞曲第五号': {
    timeSig: '2/4', keyFifths: 0, tempo: 108,
    measures: [
      [S('F#4',4), S('G4',4), N('A4',4)],
      [S('B4',4), S('C5',5), N('D5',5)],
      [N('D5',5), E('B4',4), E('D5',5)],
      [N('A4',4), R(4,'quarter')],
      [S('F#4',4), S('G4',4), N('A4',4)],
      [S('B4',4), S('C5',5), N('D5',5)],
      [N('E5',5), N('D5',5)],
      [H('A4',4)],
    ]
  },
  '德彪西月光': {
    timeSig: '9/8', keyFifths: -5, tempo: 52,
    measures: [
      [N('Db4',4), N('F4',4), N('Ab4',4), N('Db5',5), N('F4',4), N('Ab4',4), N('Db4',4), N('F4',4), N('Ab4',4)],
      [N('Db4',4), N('F4',4), N('Ab4',4), N('Db5',5), N('F4',4), N('Ab4',4), N('Db4',4), N('F4',4), N('Ab4',4)],
      [N('Eb4',4), N('Gb4',4), N('Bb4',4), N('Eb5',5), N('Gb4',4), N('Bb4',4), N('Eb4',4), N('Gb4',4), N('Bb4',4)],
      [N('Db4',4), N('F4',4), N('Ab4',4), N('Db5',5), N('F4',4), N('Ab4',4), N('Db4',4), N('F4',4), N('Ab4',4)],
    ]
  },
  '革命练习曲': {
    timeSig: '4/4', keyFifths: -3, tempo: 160,
    measures: [
      [S('Eb5',5), S('D5',5), S('Eb5',5), S('D5',5), S('Eb5',5), S('Bb4',4), S('Eb5',5), S('D5',5)],
      [S('Eb5',5), S('Bb4',4), S('Eb5',5), S('D5',5), S('Eb5',5), S('Bb4',4), S('Eb5',5), S('D5',5)],
      [S('C5',5), S('D5',5), S('Eb5',5), S('F5',5), S('Eb5',5), S('D5',5), S('C5',5), S('Bb4',4)],
      [N('Ab4',4), N('G4',4), N('F4',4), N('Eb4',4)],
      [S('Eb5',5), S('D5',5), S('Eb5',5), S('D5',5), S('Eb5',5), S('Bb4',4), S('Eb5',5), S('D5',5)],
      [N('C5',5), N('Bb4',4), N('Ab4',4), N('G4',4)],
      [N('F4',4), N('Ab4',4), N('C5',5), N('Eb5',5)],
      [W('Eb5',5)],
    ]
  },
  '即兴曲 Op.90 No.4': {
    timeSig: '3/4', keyFifths: -4, tempo: 72,
    measures: [
      [N('Ab4',4), N('C5',5), N('Eb5',5)],
      [N('Eb5',5), N('C5',5), N('Ab4',4)],
      [N('Gb4',4), N('C5',5), N('Eb5',5)],
      [N('Eb5',5), N('C5',5), N('Gb4',4)],
      [N('F4',4), N('Ab4',4), N('C5',5)],
      [N('C5',5), N('Ab4',4), N('F4',4)],
      [N('Eb4',4), N('Ab4',4), N('C5',5)],
      [N('Ab4',4), R(2,'eighth'), N('Ab4',4)],
    ]
  },
  '克罗地亚狂想曲': {
    timeSig: '4/4', keyFifths: 0, tempo: 96,
    measures: [
      [N('E4',4), N('G#4',4), N('B4',4), N('E5',5)],
      [N('D5',5), N('B4',4), N('G#4',4), N('E4',4)],
      [N('A4',4), N('C5',5), N('E5',5), N('A5',5)],
      [N('G#5',5), N('E5',5), N('C5',5), N('A4',4)],
      [N('E4',4), N('A4',4), N('C5',5), N('E5',5)],
      [N('D5',5), N('B4',4), N('G#4',4), N('E4',4)],
      [H('A4',4), H('C5',5)],
      [W('B4',4)],
    ]
  },
  '爱之梦第三首': {
    timeSig: '6/4', keyFifths: -4, tempo: 60,
    measures: [
      [N('Ab4',4), N('C5',5), N('Eb5',5), N('Ab5',5), N('Eb5',5), N('C5',5)],
      [N('Ab4',4), N('Bb4',4), N('D5',5), N('F5',5), N('D5',5), N('Bb4',4)],
      [N('Ab4',4), N('C5',5), N('Eb5',5), N('Ab5',5), N('Eb5',5), N('C5',5)],
      [N('Bb4',4), N('Eb5',5), N('G5',5), N('Bb5',5), N('G5',5), N('Eb5',5)],
    ]
  },
  '幻想即兴曲': {
    timeSig: '4/4', keyFifths: 7, tempo: 80,
    measures: [
      [S('G#4',4), S('C#5',5), S('E5',5), S('G#5',5), S('G#4',4), S('C#5',5), S('E5',5), S('G#5',5)],
      [S('G#4',4), S('C#5',5), S('E5',5), S('G#5',5), S('G#4',4), S('C#5',5), S('E5',5), S('G#5',5)],
      [S('G#4',4), S('C#5',5), S('F#5',5), S('A5',5), S('G#4',4), S('C#5',5), S('F#5',5), S('A5',5)],
      [S('G#4',4), S('C#5',5), S('E5',5), S('G#5',5), S('G#4',4), S('C#5',5), S('E5',5), S('G#5',5)],
      [N('C#5',5), N('E5',5), N('G#5',5), N('C#6',6)],
      [N('C#6',6), N('B5',5), N('A5',5), N('G#5',5)],
      [N('F#5',5), N('E5',5), N('C#5',5), N('A4',4)],
      [W('G#4',4)],
    ]
  },
  '小狗圆舞曲': {
    timeSig: '3/4', keyFifths: -5, tempo: 120,
    measures: [
      [N('Db5',5), N('F5',5), N('Ab5',5)],
      [N('Ab5',5), N('F5',5), N('Db5',5)],
      [N('Bb4',4), N('Db5',5), N('F5',5)],
      [N('F5',5), N('Db5',5), N('Bb4',4)],
      [N('Ab4',4), N('C5',5), N('Eb5',5)],
      [N('Eb5',5), N('C5',5), N('Ab4',4)],
      [N('Db5',5), N('F5',5), N('Ab5',5)],
      [N('Db5',5), R(2,'eighth'), N('Db5',5)],
    ]
  },
  '蓝色狂想曲 (简化版)': {
    timeSig: '4/4', keyFifths: 0, tempo: 88,
    measures: [
      [N('Bb4',4), N('Eb5',5), N('D5',5), N('C5',5)],
      [N('Bb4',4), N('G4',4), N('Eb4',4), R(4,'quarter')],
      [N('C5',5), N('D5',5), N('Eb5',5), N('F5',5)],
      [N('G5',5), N('F5',5), N('Eb5',5), N('D5',5)],
      [N('C5',5), N('Bb4',4), N('A4',4), N('Bb4',4)],
      [H('C5',5), H('Eb5',5)],
      [N('D5',5), N('C5',5), N('Bb4',4), N('A4',4)],
      [W('Bb4',4)],
    ]
  },
  '菊次郎的夏天': {
    timeSig: '4/4', keyFifths: 0, tempo: 100,
    measures: [
      [N('G4',4), N('A4',4), N('B4',4), N('D5',5)],
      [N('C5',5), N('B4',4), N('A4',4), N('G4',4)],
      [N('A4',4), N('B4',4), N('C5',5), N('E5',5)],
      [N('D5',5), N('C5',5), N('B4',4), N('A4',4)],
      [N('G4',4), N('B4',4), N('D5',5), N('G5',5)],
      [N('E5',5), N('D5',5), N('B4',4), N('G4',4)],
      [H('C5',5), H('E5',5)],
      [W('D5',5)],
    ]
  },
};

async function main() {
  console.log('🎼 开始生成 MusicXML 乐谱文件...\n');

  const uploadDir = path.join(process.cwd(), 'uploads/scores');
  if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
  }

  const dbScores = await prisma.score.findMany();
  let generated = 0;

  for (const dbScore of dbScores) {
    const scoreData = scores[dbScore.title];
    if (!scoreData) {
      console.log(`⚠️  未找到乐谱数据: ${dbScore.title}`);
      continue;
    }

    const xml = buildXml({
      title: dbScore.title,
      composer: dbScore.composer,
      timeSig: scoreData.timeSig,
      keyFifths: scoreData.keyFifths,
      tempo: scoreData.tempo,
      measures: scoreData.measures,
    });

    const fileName = dbScore.musicXmlPath.split('/').pop();
    const filePath = path.join(uploadDir, fileName);
    fs.writeFileSync(filePath, xml, 'utf-8');

    const fileSize = Buffer.byteLength(xml, 'utf-8');

    await prisma.score.update({
      where: { id: dbScore.id },
      data: {
        musicXmlPath: `uploads/scores/${fileName}`,
        fileSize,
      },
    });

    console.log(`✅ ${dbScore.title} → ${fileName} (${fileSize} bytes)`);
    generated++;
  }

  console.log(`\n📊 完成! 生成 ${generated}/${dbScores.length} 首乐谱`);
}

main().catch(console.error).finally(() => prisma.$disconnect());
