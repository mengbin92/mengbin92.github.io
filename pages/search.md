---
layout: page
title: Search
cover-img: "/assets/img/head/search.jpg"
---

<input type="text" id="search-input" placeholder="Search blog posts...">
<ul id="results-container"></ul>

<script>
fetch('/search-index.json')
  .then(function(response) { return response.json(); })
  .then(function(payload) {
    var docs = Array.isArray(payload.index) ? payload.index : [];
    var input = document.getElementById('search-input');
    var results = document.getElementById('results-container');

    function render(items) {
      if (!items.length) {
        results.innerHTML = '<li>No search result.</li>';
        return;
      }

      results.innerHTML = items.map(function(item) {
        return '<li><a href="' + item.url + '"><strong>' + item.title + '</strong></a><p>' +
          (item.summary || '') + '</p></li>';
      }).join('');
    }

    input.addEventListener('input', function() {
      var keyword = input.value.trim().toLowerCase();
      if (!keyword) {
        results.innerHTML = '';
        return;
      }

      var filtered = docs.filter(function(item) {
        var haystack = [item.title, item.summary, item.content, (item.tags || []).join(' '), item.category]
          .filter(Boolean)
          .join(' ')
          .toLowerCase();
        return haystack.indexOf(keyword) !== -1;
      }).slice(0, 20);

      render(filtered);
    });
  });
</script>
