# AI-Based-Personalized-Posture-Recognition-and-Concentration-Care-System
A sophisticated AI-driven framework integrating real-time posture recognition and behavioral analysis to deliver personalized ergonomic interventions and optimize cognitive concentration levels.


Rule
🚀 팀 프로젝트를 위한 깃허브(GitHub) 협업 가이드
1. 브랜치 전략 (Branch Strategy)
효율적인 코드 관리와 안정적인 배포를 위해 브랜치를 분리하여 운영합니다.

main: 배포 및 발표용 브랜치. 언제든 동작 가능한 상태를 유지해야 하며, 직접 push는 절대 금지합니다.

dev: 통합 테스트용 브랜치. 각자의 기능을 합치는 공간이며, 팀원 전원이 테스트 후 main으로 올립니다.

feat/이름: 개인 작업 브랜치. dev에서 분기하여 작업하며, 기능 완성 시 dev로 PR을 보냅니다.

2. 커밋 메시지 규칙 (Commit Message)
한 줄 설명을 원칙으로 하며, 반드시 [타입]을 앞에 붙여 가독성을 높입니다.

feat: 새 기능 추가 (예: feat: 자세 판정 함수 추가)

fix: 버그 수정 (예: fix: DB 저장 오류 수정)

docs: 문서 수정 (예: docs: README 실행 방법 추가)

test: 테스트 추가 (예: test: 시뮬레이터 단위 테스트)

refactor: 코드 정리 (예: refactor: API 응답 구조 정리)

주의: "수정함", "ㅇㅇ", "asdf" 등 내용 파악이 안 되는 메시지는 지양해 주세요.

3. PR(풀 리퀘스트) 규칙
코드의 퀄리티를 유지하기 위한 상호 검토 단계입니다.

승인 후 머지: 본인 PR은 직접 머지할 수 없습니다. 최소 팀원 1명 이상의 승인이 필요합니다.

설명 필수: "무엇을 만들었는지"와 "어떻게 테스트했는지"를 최소 2줄 이상 작성합니다.

기능 단위: 한 PR에는 하나의 기능만 담아 리뷰 효율을 높입니다.

알림 공유: PR을 올린 후에는 반드시 카톡 단톡방에 링크를 공유합니다.

4. 충돌(Conflict) 발생 시 해결법
최신화: git pull origin dev로 dev 브랜치를 최신 상태로 가져옵니다.

병합: 내 브랜치에 dev를 합쳐(git merge dev) 충돌 위치를 확인합니다.

직접 수정: VS Code 등에서 충돌 파일을 열어 직접 코드를 수정한 후 커밋합니다.

협의: 혼자 해결하기 어렵다면 관련 팀원과 함께 확인하며, 무작정 덮어쓰지 않습니다.

5. 기타 팀 규칙
README.md: 새로운 팀원이 문서만 보고도 서버를 실행할 수 있도록 항상 최신 상태를 유지합니다. 
환경 변수 관리: .env 파일은 절대 공유하지 않고(gitignore 등록), 대신 .env.example 파일을 공유합니다.

보호 설정: 실수 방지를 위해 GitHub 레포 설정에서 main 브랜치 보호 규칙(Branch Protection)을 활성화합니다.

