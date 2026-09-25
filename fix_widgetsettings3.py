import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/WidgetSettings/index.tsx', 'r') as f:
    code = f.read()

# Render block
if '<ClosingEntryWidget />' not in code:
    code = code.replace("{activeWidget === 'api' && (", """{(activeWidget as string) === 'closing-entry-access' && (
            <div className="widget-modal">
              <div className="modal-header">
                <h2>Closing Entry Access Control</h2>
                <button className="close-btn" onClick={() => setActiveWidget(null)}>
                  <X size={20} />
                </button>
              </div>
              <div className="modal-body" style={{ padding: '20px' }}>
                <ClosingEntryWidget />
              </div>
            </div>
          )}

          {activeWidget === 'api' && (""")

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/WidgetSettings/index.tsx', 'w') as f:
    f.write(code)
