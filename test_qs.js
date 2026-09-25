const qs = require('qs');

const query = 'where[user][equals]=123&where[date][greater_than_equal]=2026&where[date][less_than_equal]=2027';
console.log(JSON.stringify(qs.parse(query), null, 2));

const query2 = 'where[and][0][user][equals]=123&where[and][1][date][greater_than_equal]=2026&where[and][2][date][less_than_equal]=2027';
console.log(JSON.stringify(qs.parse(query2), null, 2));
