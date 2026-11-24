chrome.storage.local.set({k: 42}, function(){
  chrome.storage.local.get('k', function(r){
    document.getElementById('o').textContent = 'stored:' + r.k;
    window.__popupDone = 'stored:' + r.k;
  });
});
