'use strict';
const sentences = [
 {name:'한국어 → 영어',input:'이 내용 한번 확인해 줄래?',meaning:'이 내용을 확인해 줄래요?',answers:{casual:'Can you take a look at this?',polite:'Could you take a look at this, please?',formal:'Would you please review this?'},note:'같은 부탁도 상대와 상황에 맞춰 어투를 바꿀 수 있습니다.'},
 {name:'문법 교정',input:"She don't like coffee.",meaning:'그녀는 커피를 좋아하지 않아요.',answers:{casual:"She doesn't like coffee.",polite:"She doesn't like coffee.",formal:'She does not like coffee.'},note:'3인칭 단수 주어에는 don’t 대신 doesn’t를 씁니다. 사실을 덧붙이지 않고 문법을 교정합니다.'},
 {name:'지역별 표현',input:'주말에 시내에서 영화 볼래?',meaning:'주말에 시내에서 영화 볼래요?',answers:{casual:'Want to catch a movie downtown this weekend?',polite:'Would you like to see a movie downtown this weekend?',formal:'Would you be interested in seeing a film downtown this weekend?'},regional:{uk:{casual:'Fancy seeing a film in town this weekend?',polite:'Would you like to see a film in town this weekend?',formal:'Would you be interested in seeing a film in town this weekend?'},australia:{casual:'Want to catch a movie in the city this weekend?',polite:'Would you like to see a movie in the city this weekend?',formal:'Would you be interested in seeing a film in the city this weekend?'}},note:'지역에 따라 단어뿐 아니라 제안하는 방식도 달라질 수 있습니다. 지역 설정을 바꿔 보세요.'}
];
const words = [
 {name:'영어 숙어',input:'call it a day',text:'오늘은 여기까지 하다',meaning:'하던 일이나 활동을 마치기로 할 때 쓰는 표현입니다.',note:'We’ve done enough. Let’s call it a day.\n충분히 했어. 오늘은 여기까지 하자.'},
 {name:'영어 단어',input:'thoughtful',text:'사려 깊은 · 세심한',meaning:'다른 사람의 마음과 필요를 잘 헤아리는 모습을 뜻합니다.',note:'That was very thoughtful of you.\n정말 세심하게 신경 써 줬네.'},
 {name:'한국어 → 영어',input:'아쉽다',text:'That’s a shame.',meaning:'일이 기대와 달라 아쉬울 때 쓰는 표현입니다.',note:'‘아쉽다’는 문맥에 따라 달라집니다. 기회를 놓쳤다면 “I wish I’d had the chance.”처럼 표현할 수 있습니다.'}
];
let mode='sentence', tone='casual';
const scenario=document.querySelector('#scenario');
const region=document.querySelector('#region');
function render(){
 const index=Number(scenario.value)||0;
 const item=(mode==='sentence'?sentences:words)[index];
 document.querySelector('#user-text').textContent=item.input;
 const answer=document.querySelector('#answer-text');
 answer.textContent=mode==='sentence'?(item.regional?.[region.value]?.[tone]||item.answers[tone]):item.text;
 answer.lang=mode==='sentence'||index===2?'en':'ko';
 document.querySelector('#answer-meta').textContent=mode==='sentence'?'ENGLISH EXPRESSION':'MEANING & USAGE';
 document.querySelector('#answer-meaning').textContent=item.meaning;
 document.querySelector('#answer-note').textContent=item.note;
}
function setMode(value){
 mode=value;
 document.querySelectorAll('[data-mode]').forEach(button=>{const selected=button.dataset.mode===mode;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1;});
 document.querySelector('#demo-panel').setAttribute('aria-labelledby',mode+'-tab');
 scenario.replaceChildren(...(mode==='sentence'?sentences:words).map((item,index)=>new Option(item.name,String(index))));
 document.querySelector('#tone-wrap').hidden=mode!=='sentence';
 document.querySelector('.region-control').hidden=mode!=='sentence';
 render();
}
document.querySelectorAll('[data-mode]').forEach(button=>{button.addEventListener('click',()=>setMode(button.dataset.mode));button.addEventListener('keydown',event=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){event.preventDefault();const next=event.key==='Home'?'sentence':event.key==='End'?'word':mode==='sentence'?'word':'sentence';setMode(next);document.querySelector('#'+next+'-tab').focus();}});});
document.querySelectorAll('[data-tone]').forEach(button=>button.addEventListener('click',()=>{tone=button.dataset.tone;document.querySelectorAll('[data-tone]').forEach(item=>item.setAttribute('aria-pressed',String(item.dataset.tone===tone)));render();}));
scenario.addEventListener('change',render);region.addEventListener('change',render);
document.querySelector('#year').textContent=new Date().getFullYear();setMode(mode);
