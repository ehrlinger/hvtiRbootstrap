* `boot_pool_chunks()` refuses chunks that disagree on `resampled`
  (`"patients"` against `"rows"`), and the pooled object carries the agreed
  value. A chunk that records no `resampled` predates patient resampling and
  is read as `"rows"`, so older chunks still pool.
