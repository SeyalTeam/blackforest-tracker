import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/WidgetSettings/index.tsx', 'r') as f:
    code = f.read()

# Render block
if 'closing-entry-access' not in code.split('LIVE API')[0]:
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

# Tile block
if 'Closing Entry Access' not in code:
    code = code.replace("onClick={() => setActiveWidget('api')}", """onClick={() => setActiveWidget('api')}
          >
            <Globe className="tile-icon" size={48} />
            <span className="tile-label">LIVE API</span>
          </button>

          <button
            type="button"
            className={`tile ${(activeWidget as string) === 'closing-entry-access' ? 'active' : ''}`}
            onClick={() => setActiveWidget('closing-entry-access' as any)}
          >
            <Lock className="tile-icon" size={48} />
            <span className="tile-label">Closing Entry Access</span>
          """)

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/components/WidgetSettings/index.tsx', 'w') as f:
    f.write(code)
