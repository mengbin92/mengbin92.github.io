---
layout: page
permalink: "sitemap"
title: Sitemap
---

<section class="sitemap-section">
  <h2>All Posts</h2>
  <div class="sitemap-table-wrap">
    <table class="sitemap-table">
      <thead>
        <tr>
          <th>Date</th>
          <th>Title</th>
          <th>Tags</th>
        </tr>
      </thead>
      <tbody id="sitemap-posts-body">
        <tr>
          <td colspan="3">Loading posts...</td>
        </tr>
      </tbody>
    </table>
  </div>
</section>

<section class="sitemap-section">
  <h2>All Pages</h2>
  <ul class="sitemap-pages" id="sitemap-pages-list"></ul>
</section>

<script>
const staticPages = [
  { title: 'Home', url: '/' },
  { title: 'About', url: '/pages/aboutme/' },
  { title: 'Search', url: '/search/' },
  { title: 'Tags', url: '/tags/' },
  { title: 'Categories', url: '/categories/' },
  { title: 'Sitemap', url: '/sitemap/' }
];

function formatDate(input) {
  if (!input) return '';
  const date = new Date(input);
  if (Number.isNaN(date.getTime())) return input;
  return date.toISOString().slice(0, 10);
}

function renderPages() {
  const list = document.getElementById('sitemap-pages-list');
  list.innerHTML = staticPages.map((page) => {
    return '<li><a href="' + page.url + '">' + page.title + '</a></li>';
  }).join('');
}

function renderPosts(posts) {
  const body = document.getElementById('sitemap-posts-body');
  if (!posts.length) {
    body.innerHTML = '<tr><td colspan="3">No posts found.</td></tr>';
    return;
  }

  body.innerHTML = posts.map((post) => {
    const tags = Array.isArray(post.tags) ? post.tags.map((tag) => {
      return '<a class="sitemap-tag" href="/tags/' + encodeURIComponent(tag.toLowerCase()) + '/">' + tag + '</a>';
    }).join(' ') : '';

    return '<tr>' +
      '<td>' + formatDate(post.date) + '</td>' +
      '<td><a href="' + post.url + '">' + post.title + '</a></td>' +
      '<td>' + tags + '</td>' +
    '</tr>';
  }).join('');
}

renderPages();

fetch('/search-index-min.json')
  .then((response) => response.json())
  .then((payload) => {
    const posts = Array.isArray(payload.index) ? payload.index.slice() : [];
    posts.sort((a, b) => String(b.date).localeCompare(String(a.date)));
    renderPosts(posts);
  })
  .catch(() => {
    const body = document.getElementById('sitemap-posts-body');
    body.innerHTML = '<tr><td colspan="3">Failed to load posts.</td></tr>';
  });
</script>
