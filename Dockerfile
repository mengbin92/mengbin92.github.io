FROM jekyll/jekyll

COPY --chown=jekyll:jekyll Gemfile .

CMD ["jekyll", "serve"]