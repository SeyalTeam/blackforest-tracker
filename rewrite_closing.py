import re

with open('lib/manager_closing_report.dart', 'r') as f:
    code = f.read()

# Replace class names
code = code.replace('BranchBillingReportScreen', 'BranchClosingReportScreen')
code = code.replace('_BranchBillingReportScreenState', '_BranchClosingReportScreenState')
code = code.replace('ManagerBillingReportScreen', 'ManagerClosingReportScreen')
code = code.replace('_ManagerBillingReportScreenState', '_ManagerClosingReportScreenState')

# Replace API call
code = code.replace('fetchBranchBillingReport', 'fetchClosingEntryReport')
code = code.replace('_billingReport', '_closingReport')

# Replace titles and text
code = code.replace("'Billing Report'", "'Closing Entry Report'")

# Replace grid metrics rendering
# In the original, it builds a grid with TOTAL BILLS, CASH, UPI, CARD, TOTAL SALES.
# We will just change it slightly for Closing Entry
# Instead of doing complex regex, we can just let it render what it has, 
# as the keys like 'totalBills', 'cash', 'upi', 'card', 'totalSales' are ALL present in closingEntry!
# Actually, the Closing Entry stats have exactly the same keys for money!
# 'totalBills', 'cash', 'upi', 'card', 'totalAmount' -> wait, the total in closingEntry is 'totalSales' and 'systemSales'.

with open('lib/manager_closing_report.dart', 'w') as f:
    f.write(code)
