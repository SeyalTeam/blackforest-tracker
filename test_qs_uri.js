const qs = require('qs');

const urlString = 'where%5Buser%5D%5Bequals%5D=6a51c3edec08231d01c3a3d1&where%5Bdate%5D%5Bgreater_than_equal%5D=2026-08-31T18:30:00.000Z&where%5Bdate%5D%5Bless_than_equal%5D=2026-09-30T18:29:59.000Z&limit=100';

console.log(JSON.stringify(qs.parse(urlString), null, 2));
