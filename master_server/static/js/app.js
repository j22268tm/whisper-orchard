const { createApp, ref } = Vue;

createApp({
    delimiters: ['[[', ']]'],
    
    setup() {
        const file = ref(null);
        const isDragging = ref(false);
        const status = ref('idle');
        const resultText = ref('');
        const showTimestamps = ref(false);
        const resultSegments = ref([]);
        const errorMessage = ref('');
        const workers = ref([]);
        const showAddWorker = ref(false);
        const newWorkerUrl = ref('');
        const allWorkers = ref([]);
        const history = ref([]);
        const stats = ref({ workers: { online: 0, busy: 0, total: 0 }, jobs: { processing: 0, completed: 0, failed: 0 } });
        const selectedJob = ref(null);
        const showJobDetail = ref(false);
        const currentJobId = ref(null);
        const currentJobStatus = ref('idle');
        const usePurifier = ref(true);
        const purifierCompleted = ref(false);
        let pollInterval = null;

        // Purifier設定をAPI経由で保存
        const savePurifierPreference = async (value) => {
            try {
                await fetch('/preferences/purifier', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ usePurifier: value })
                });
            } catch (e) {
                console.error('Failed to save purifier preference:', e);
            }
        };

        // Purifier設定をAPIから取得
        const loadPurifierPreference = async () => {
            try {
                const response = await fetch('/preferences/purifier');
                const data = await response.json();
                usePurifier.value = data.usePurifier;
            } catch (e) {
                console.error('Failed to load purifier preference:', e);
            }
        };

        // オンラインワーカーを取得
        const fetchWorkers = async () => {
            try {
                const response = await fetch('/workers');
                const data = await response.json();
                workers.value = data.workers.map(w => ({
                    id: w.id,
                    url: w.url,
                    progress: 0,
                    status: w.status || 'online',
                    current_chunk: w.current_chunk || null,
                    last_seen: w.last_seen || null
                }));
                // 全ワーカーリストも取得
                allWorkers.value = data.workers.map(w => w.url);
            } catch (e) {
                console.error('Failed to fetch workers:', e);
                workers.value = [];
                allWorkers.value = [];
            }
        };

        // 統計情報取得
        const fetchStats = async () => {
            try {
                const response = await fetch('/stats');
                const data = await response.json();
                stats.value = data;
            } catch (e) {
                console.error('Failed to fetch stats:', e);
            }
        };

        // ジョブ履歴取得
        const fetchJobs = async () => {
            try {
                const response = await fetch('/jobs');
                const data = await response.json();
                history.value = data.jobs.map(job => ({
                    id: job.job_id,
                    name: job.filename || 'Unknown',
                    status: job.status,
                    created_at: job.created_at,
                    completed_at: job.completed_at,
                    progress: job.progress || 0
                }));
            } catch (e) {
                console.error('Failed to fetch jobs:', e);
            }
        };

        // ジョブ詳細取得
        const fetchJobDetail = async (jobId) => {
            try {
                const response = await fetch(`/jobs/${jobId}`);
                const data = await response.json();
                selectedJob.value = data;
                showJobDetail.value = true;
            } catch (e) {
                console.error('Failed to fetch job detail:', e);
                errorMessage.value = 'ジョブ詳細の取得に失敗しました';
            }
        };

        // 現在のジョブ状態をポーリング
        const pollCurrentJob = async () => {
            if (!currentJobId.value) return;
            
            try {
                const response = await fetch(`/jobs/${currentJobId.value}`);
                const data = await response.json();

                // 前のステータスを保存
                const previousStatus = currentJobStatus.value;
                currentJobStatus.value = data.status;

                console.log('[pollCurrentJob] status:', data.status, '| previousStatus:', previousStatus, '| purifierCompleted:', purifierCompleted.value, '| status(ref):', status.value);

                if (data.status === 'purifier_completed') {
                    console.log('[purifier] purifier_completed検知 → 完了アニメーション開始');
                    purifierCompleted.value = true;
                    currentJobStatus.value = 'purifier_completed'; 
                    status.value = 'idle';
                    // 1.5秒後にフラグをリセット（完了アニメーション表示用）
                    setTimeout(() => {
                        purifierCompleted.value = false;
                        console.log('[purifier] 完了アニメーション終了 → purifierCompleted=false');
                    }, 1500);
                }

                // ステータスに応じてUI更新
                if (data.status === 'purifying') {
                    if (status.value !== 'cleaning') {
                        console.log('[purifier] purifying検知 → cleaningアニメーション開始');
                    }
                    status.value = 'cleaning';
                } else if (data.status === 'splitting' || data.status === 'processing' || data.status === 'aggregating') {
                    if (status.value !== 'transcribing') {
                        console.log('[pipe/tree] splitting/processing/aggregating検知 → transcribingアニメーション開始');
                    }
                    status.value = 'transcribing';
                    if (data.chunks && data.chunks.length > 0) {
                        const completedChunks = data.chunks.filter(c => c.status === 'completed').length;
                        const totalChunks = data.chunks.length;
                        workers.value.forEach(w => {
                            const processingChunk = data.chunks.find(c => 
                                c.status === 'processing' && c.worker_url === w.url
                            );
                            
                            if (processingChunk) {
                                // 処理中の場合
                                w.status = 'busy';
                                w.current_chunk = processingChunk.chunk_id.split('_').pop();
                                w.progress = Math.min(95, (completedChunks / totalChunks) * 100 + Math.random() * 10);
                            } else {
                                // アイドルまたは完了
                                w.status = 'online';
                                w.current_chunk = null;
                                w.progress = (completedChunks / totalChunks) * 100;
                            }
                        });
                    }
                } else if (data.status === 'completed') {
                    workers.value.forEach(w => {
                        w.progress = 100;
                        w.status = 'online';
                        w.current_chunk = null;
                    });
                    stopPolling();
                } else if (data.status === 'failed') {
                    stopPolling();
                    errorMessage.value = `ジョブが失敗しました\n\n${data.error || '不明なエラー'}`;
                    status.value = 'idle';
                }
            } catch (e) {
                console.error('Failed to poll job:', e);
            }
        };

        const startPolling = () => {
            stopPolling();
            pollInterval = setInterval(() => {
                fetchStats();
                fetchJobs();
                fetchWorkers();
                pollCurrentJob();
            }, 2000);
        };

        const stopPolling = () => {
            if (pollInterval) {
                clearInterval(pollInterval);
                pollInterval = null;
            }
        };

        const handleDrop = (e) => {
            isDragging.value = false;
            const droppedFiles = e.dataTransfer.files;
            if (droppedFiles.length > 0) file.value = droppedFiles[0];
        };

        const handleFileSelect = (e) => {
            if (e.target.files.length > 0) file.value = e.target.files[0];
        };

        const startProcess = async () => {
            if (!file.value) return;
            resultText.value = '';
            
            if (workers.value.length === 0) {
                errorMessage.value = 'Workerがいません！\n\nWorker Nodeを起動してから再度お試しください。';
                return;
            }
            
            const formData = new FormData();
            formData.append('file', file.value);

            status.value = 'cleaning';
            currentJobStatus.value = 'purifying';
            
            try {
                const responsePromise = fetch('/submit', {
                    method: 'POST',
                    body: formData
                });

                await new Promise(r => setTimeout(r, 5000));

                status.value = 'transcribing';
                
                const progressInterval = setInterval(() => {
                    workers.value.forEach(w => {
                        if (w.progress < 95) {
                            w.progress += Math.random() * 15;
                        }
                    });
                }, 300);
                
                const response = await responsePromise;
                clearInterval(progressInterval);
                
                if (!response.ok) {
                    throw new Error('Server returned error: ' + response.status);
                }

                const data = await response.json();
                
                // ジョブIDを保存してポーリング開始
                if (data.job_id) {
                    currentJobId.value = data.job_id;
                    startPolling();
                }
                
                if (data.status === 'error') {
                    throw new Error(data.message || 'Unknown error');
                }
                
                workers.value.forEach(w => w.progress = 100);
                await new Promise(r => setTimeout(r, 500));
                
                resultSegments.value = data.result.segments || [];
                
                finishProcess(data.result.text);

            } catch (e) {
                errorMessage.value = 'エラーが発生しました\n\n' + e.message;
                status.value = 'idle';
                workers.value.forEach(w => w.progress = 0);
            }
        };

        const finishProcess = async (text) => {
            await new Promise(r => setTimeout(r, 500));
            stopPolling();
            status.value = 'idle';
            currentJobId.value = null;
            currentJobStatus.value = 'idle';
            workers.value.forEach(w => w.progress = 0);
            
            for (let i = 0; i < text.length; i++) {
                resultText.value += text[i];
                await new Promise(r => setTimeout(r, 30));
            }
        };

        const copyText = () => {
            navigator.clipboard.writeText(resultText.value);
        };

        const toggleTimestamps = () => {
            showTimestamps.value = !showTimestamps.value;
        };

        const addWorker = async () => {
            if (!newWorkerUrl.value.trim()) {
                errorMessage.value = 'Worker URLを入力してください';
                return;
            }

            try {
                const response = await fetch('/workers/add', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ url: newWorkerUrl.value })
                });

                const data = await response.json();

                if (!response.ok) {
                    throw new Error(data.error || '追加に失敗しました');
                }

                newWorkerUrl.value = '';
                showAddWorker.value = false;
                await fetchWorkers();
            } catch (e) {
                errorMessage.value = 'ワーカー追加エラー\n\n' + e.message;
            }
        };

        const removeWorker = async (workerUrl) => {
            if (!confirm(`${workerUrl} を削除しますか？`)) {
                return;
            }

            try {
                const response = await fetch('/workers/remove', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ url: workerUrl })
                });

                const data = await response.json();

                if (!response.ok) {
                    throw new Error(data.error || '削除に失敗しました');
                }

                await fetchWorkers();
            } catch (e) {
                errorMessage.value = 'ワーカー削除エラー\n\n' + e.message;
            }
        };

        const getStatusBadgeClass = (status) => {
            const classes = {
                'created': 'bg-gray-100 text-gray-600',
                'purifying': 'bg-blue-100 text-blue-600',
                'splitting': 'bg-yellow-100 text-yellow-600',
                'processing': 'bg-purple-100 text-purple-600',
                'aggregating': 'bg-indigo-100 text-indigo-600',
                'completed': 'bg-green-100 text-green-600',
                'failed': 'bg-red-100 text-red-600'
            };
            return classes[status] || 'bg-gray-100 text-gray-600';
        };

        const formatTime = (timestamp) => {
            if (!timestamp) return 'N/A';
            const date = new Date(timestamp);
            const now = new Date();
            const diff = Math.floor((now - date) / 1000);
            
            if (diff < 60) return `${diff}秒前`;
            if (diff < 3600) return `${Math.floor(diff / 60)}分前`;
            if (diff < 86400) return `${Math.floor(diff / 3600)}時間前`;
            return `${Math.floor(diff / 86400)}日前`;
        };

        const getWorkerStatusIcon = (workerStatus) => {
            const icons = {
                'online': 'check_circle',
                'busy': 'hourglass_empty',
                'offline': 'cancel'
            };
            return icons[workerStatus] || 'help';
        };

        const getWorkerStatusColor = (workerStatus) => {
            const colors = {
                'online': 'text-green-500',
                'busy': 'text-yellow-500',
                'offline': 'text-red-500'
            };
            return colors[workerStatus] || 'text-gray-500';
        };

        // 初期ロード時にデータ取得とポーリング開始
        fetchWorkers();
        fetchStats();
        fetchJobs();
        loadPurifierPreference();
        startPolling();

        // usePurifierの変更を監視
        Vue.watch(() => usePurifier.value, (newValue) => {
            savePurifierPreference(newValue);
        });

        return {
            file,
            isDragging,
            status,
            resultText,
            showTimestamps,
            resultSegments,
            errorMessage,
            workers,
            showAddWorker,
            newWorkerUrl,
            allWorkers,
            history,
            stats,
            selectedJob,
            showJobDetail,
            currentJobStatus,
            usePurifier,
            purifierCompleted,
            handleDrop,
            handleFileSelect,
            startProcess,
            copyText,
            toggleTimestamps,
            addWorker,
            removeWorker,
            fetchJobDetail,
            getStatusBadgeClass,
            formatTime,
            getWorkerStatusIcon,
            getWorkerStatusColor
        };
    }
}).mount('#app');
