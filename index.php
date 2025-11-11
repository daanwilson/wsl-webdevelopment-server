<?php
$currentDir = __DIR__;
//$currentDir = '/mnt/h/';
$directories = [];

try {
    // FilesystemIterator slaat automatisch . en .. over
    $iterator = new FilesystemIterator(
        $currentDir,
        FilesystemIterator::SKIP_DOTS | FilesystemIterator::UNIX_PATHS
    );
    
    foreach ($iterator as $fileInfo) {
        if ($fileInfo->isDir()) {
            $directories[] = $fileInfo->getFilename();
        }
    }
    
    // Sorteer alfabetisch
    sort($directories, SORT_NATURAL | SORT_FLAG_CASE);
    
} catch (Exception $e) {
    // Error handling
    $directories = [];
    $error = "Fout bij het lezen van de directory: " . htmlspecialchars($e->getMessage());
}
?>
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Directory Browser</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 2rem 0;
        }
        .container {
            max-width: 900px;
        }
        .card {
            border: none;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            border-radius: 15px;
        }
        .directory-card {
            transition: all 0.3s ease;
            border: 2px solid #e9ecef;
            border-radius: 10px;
            background: white;
        }
        .directory-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 20px rgba(0,0,0,0.15);
            border-color: #667eea;
        }
        .directory-icon {
            font-size: 2.5rem;
            color: #667eea;
        }
        .search-box {
            border-radius: 50px;
            border: 2px solid #e9ecef;
            padding: 0.75rem 1.5rem;
        }
        .search-box:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
        }
        .no-results {
            display: none;
            color: #6c757d;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <div class="card-body p-4">
                <h1 class="text-center mb-4">
                    <i class="bi bi-folder2-open"></i> Mijn projecten
                </h1>
                
                <!-- Zoekbalk -->
                <div class="mb-4">
                    <input type="text" 
                           id="searchInput" 
                           class="form-control search-box" 
                           placeholder="🔍 Zoek naar een map..."
                           autocomplete="off">
                </div>

                <!-- Aantal mappen -->
                <p class="text-muted mb-3">
                    <span id="resultCount"><?php echo count($directories); ?></span> 
                    map(pen) gevonden in: <code><?php echo htmlspecialchars($currentDir); ?></code>
                </p>
                
                <?php if (isset($error)): ?>
                    <div class="alert alert-danger" role="alert">
                        <i class="bi bi-exclamation-triangle"></i> <?php echo $error; ?>
                    </div>
                <?php endif; ?>

                <!-- Directory lijst -->
                <div id="directoryList" class="row g-3"></div>

                <!-- Geen resultaten melding -->
                <div id="noResults" class="no-results text-center py-5">
                    <i class="bi bi-search" style="font-size: 3rem;"></i>
                    <h4 class="mt-3">Geen mappen gevonden</h4>
                    <p class="text-muted">Probeer een andere zoekterm</p>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Directory data vanuit PHP
        const directories = <?php echo json_encode($directories); ?>;
        
        // Virtuele scroll configuratie
        const ITEMS_PER_PAGE = 50;
        let currentPage = 1;
        let filteredDirectories = [...directories];
        
        const searchInput = document.getElementById('searchInput');
        const directoryList = document.getElementById('directoryList');
        const noResults = document.getElementById('noResults');
        const resultCount = document.getElementById('resultCount');
        
        // Debounce functie voor betere performance
        function debounce(func, wait) {
            let timeout;
            return function executedFunction(...args) {
                const later = () => {
                    clearTimeout(timeout);
                    func(...args);
                };
                clearTimeout(timeout);
                timeout = setTimeout(later, wait);
            };
        }
        
        // Render functie met virtuele scrolling
        function renderDirectories() {
            const itemsToShow = currentPage * ITEMS_PER_PAGE;
            const visibleDirs = filteredDirectories.slice(0, itemsToShow);
            
            if (visibleDirs.length === 0) {
                directoryList.style.display = 'none';
                noResults.style.display = 'block';
                resultCount.textContent = '0';
                return;
            }
            
            directoryList.style.display = '';
            noResults.style.display = 'none';
            resultCount.textContent = filteredDirectories.length;
            
            // Gebruik DocumentFragment voor betere performance
            const fragment = document.createDocumentFragment();
            
            visibleDirs.forEach(dir => {
                const col = document.createElement('div');
                col.className = 'col-md-6 col-lg-4 directory-item';
                
                col.innerHTML = `
                    <a href="http://localhost/${encodeURIComponent(dir)}" 
                       target="_blank" 
                       class="text-decoration-none">
                        <div class="directory-card p-3">
                            <div class="d-flex align-items-center">
                                <div class="directory-icon me-3">
                                    <i class="bi bi-folder-fill"></i>
                                </div>
                                <div class="flex-grow-1">
                                    <h5 class="mb-0 text-dark">${escapeHtml(dir)}</h5>
                                    <small class="text-muted">
                                        <i class="bi bi-box-arrow-up-right"></i> Open in nieuw tabblad
                                    </small>
                                </div>
                            </div>
                        </div>
                    </a>
                `;
                
                fragment.appendChild(col);
            });
            
            directoryList.innerHTML = '';
            directoryList.appendChild(fragment);
            
            // Toon "Laad meer" knop indien nodig
            if (itemsToShow < filteredDirectories.length) {
                showLoadMoreButton();
            }
        }
        
        // HTML escape functie
        function escapeHtml(text) {
            const map = {
                '&': '&amp;',
                '<': '&lt;',
                '>': '&gt;',
                '"': '&quot;',
                "'": '&#039;'
            };
            return text.replace(/[&<>"']/g, m => map[m]);
        }
        
        // Laad meer knop
        function showLoadMoreButton() {
            const existingBtn = document.getElementById('loadMoreBtn');
            if (existingBtn) existingBtn.remove();
            
            const btn = document.createElement('div');
            btn.id = 'loadMoreBtn';
            btn.className = 'col-12 text-center mt-3';
            btn.innerHTML = `
                <button class="btn btn-primary btn-lg" onclick="loadMore()">
                    <i class="bi bi-arrow-down-circle"></i> Laad meer mappen
                </button>
            `;
            directoryList.appendChild(btn);
        }
        
        // Laad meer functie
        window.loadMore = function() {
            currentPage++;
            renderDirectories();
        };
        
        // Zoekfunctie met debounce
        const performSearch = debounce(function() {
            const searchTerm = searchInput.value.toLowerCase().trim();
            currentPage = 1;
            
            if (searchTerm === '') {
                filteredDirectories = [...directories];
            } else {
                filteredDirectories = directories.filter(dir => 
                    dir.toLowerCase().includes(searchTerm)
                );
            }
            
            renderDirectories();
        }, 300);
        
        searchInput.addEventListener('input', performSearch);
        
        // Infinite scroll (optioneel)
        let isLoading = false;
        window.addEventListener('scroll', function() {
            if (isLoading) return;
            
            const scrollPosition = window.innerHeight + window.scrollY;
            const threshold = document.body.offsetHeight - 500;
            
            if (scrollPosition >= threshold && currentPage * ITEMS_PER_PAGE < filteredDirectories.length) {
                isLoading = true;
                currentPage++;
                renderDirectories();
                setTimeout(() => isLoading = false, 100);
            }
        });
        
        // Initiële render
        renderDirectories();
        searchInput.focus();
    </script>
</body>
</html>