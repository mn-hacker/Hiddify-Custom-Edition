import re

with open('dashboard.html', 'r', encoding='utf-8') as f:
    content = f.read()

live_js = """
        /* --- Live Data Simulation --- */
        function animateSparkline(svgElement) {
            const paths = svgElement.querySelectorAll('path');
            let linePath, fillPath;
            paths.forEach(p => {
                if (p.classList.contains('line')) linePath = p;
                else fillPath = p;
            });
            
            if (!linePath) return;

            setInterval(() => {
                let d = linePath.getAttribute('d');
                let parts = d.split(' L');
                let points = parts.map(p => p.replace('M', '').trim());
                
                let newPoints = [];
                for (let i = 0; i < points.length - 1; i++) {
                    let curr = points[i].split(',');
                    let next = points[i+1].split(',');
                    newPoints.push(curr[0] + ',' + next[1]);
                }
                
                let lastX = points[points.length - 1].split(',')[0];
                let oldY = parseFloat(points[points.length - 1].split(',')[1]);
                let randDiff = (Math.random() - 0.5) * 15;
                let newY = oldY + randDiff;
                if (newY < 5) newY = 5;
                if (newY > 45) newY = 45;
                
                newPoints.push(lastX + ',' + newY.toFixed(1));
                
                let newD = 'M' + newPoints.join(' L');
                linePath.setAttribute('d', newD);
                
                if (fillPath) {
                    let newFillD = newD + ' V50 H0 Z';
                    fillPath.setAttribute('d', newFillD);
                }
            }, 2000);
        }

        document.querySelectorAll('svg.sparkline:not(.barchart)').forEach(svg => animateSparkline(svg));

        function updateCardValue(titleText, generatorFunc, keepSpan = false) {
            document.querySelectorAll('.card-title').forEach(title => {
                if (title.textContent.trim().toUpperCase() === titleText.toUpperCase()) {
                    const valEl = title.parentElement.querySelector('.card-value');
                    if (valEl) {
                        setInterval(() => {
                            if (keepSpan) {
                                const spanHtml = valEl.querySelector('span') ? valEl.querySelector('span').outerHTML : '';
                                valEl.innerHTML = generatorFunc() + ' ' + spanHtml;
                            } else {
                                valEl.textContent = generatorFunc();
                            }
                        }, 2000);
                    }
                }
            });
        }

        let currentCpu = 23.9;
        updateCardValue('CPU Usage', () => {
            currentCpu += (Math.random() - 0.5) * 8;
            if(currentCpu < 2) currentCpu = 2;
            if(currentCpu > 98) currentCpu = 98;
            return currentCpu.toFixed(1) + '%';
        });

        let currentMem = 79.0;
        updateCardValue('Memory Usage', () => {
            currentMem += (Math.random() - 0.5) * 3;
            if(currentMem < 50) currentMem = 50;
            if(currentMem > 95) currentMem = 95;
            return currentMem.toFixed(1) + '%';
        });

        let currentNet = 4.1;
        updateCardValue('Network History', () => {
            currentNet += (Math.random() - 0.5) * 2;
            if(currentNet < 0.5) currentNet = 0.5;
            return currentNet.toFixed(1) + ' MB/s';
        });

        updateCardValue('INCOMING SPEED', () => {
            return parseFloat(Math.random() * 5 + 1).toFixed(2) + ' MB/s';
        });

        updateCardValue('OUTGOING SPEED', () => {
            return parseFloat(Math.random() * 5 + 1).toFixed(2) + ' MB/s';
        });
        
        // Storage cards
        let memUsage = 1.33;
        updateCardValue('MEMORY USAGE', () => {
            memUsage += (Math.random() - 0.5) * 0.1;
            if(memUsage < 1.0) memUsage = 1.0;
            if(memUsage > 1.8) memUsage = 1.8;
            return memUsage.toFixed(2) + ' GB';
        }, true);
        
        updateCardValue('THREADS', () => {
            return Math.floor(Math.random() * 20 + 30).toString();
        });

        updateCardValue('PANEL MEMORY', () => {
            return parseFloat(Math.random() * 50 + 550).toFixed(2) + ' MB';
        });

        setInterval(() => {
            document.querySelectorAll('svg.barchart rect').forEach(rect => {
                if(Math.random() > 0.4) {
                    let h = parseFloat(rect.getAttribute('height'));
                    let y = parseFloat(rect.getAttribute('y'));
                    let diff = (Math.random() - 0.5) * 12;
                    let newH = h + diff;
                    let newY = y - diff;
                    if (newH > 5 && newH < 45 && newY > 0) {
                        rect.setAttribute('height', newH.toFixed(1));
                        rect.setAttribute('y', newY.toFixed(1));
                    }
                }
            });
        }, 1500);
"""

if '/* --- Live Data Simulation --- */' not in content:
    content = content.replace('</script>\n</body>', live_js + '\n</script>\n</body>')
    with open('dashboard.html', 'w', encoding='utf-8') as f:
        f.write(content)
    print("Live data simulation added to dashboard.html")
else:
    # Update existing live data script
    content = re.sub(r'/\* --- Live Data Simulation --- \*/.*?</script>', live_js + '\n</script>', content, flags=re.DOTALL)
    with open('dashboard.html', 'w', encoding='utf-8') as f:
        f.write(content)
    print("Live data simulation updated in dashboard.html")
