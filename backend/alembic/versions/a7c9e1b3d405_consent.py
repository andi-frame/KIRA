"""consent for health data processing

Revision ID: a7c9e1b3d405
Revises: f5a1c3d7e902
Create Date: 2026-10-15 14:20:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'a7c9e1b3d405'
down_revision: Union[str, Sequence[str], None] = 'f5a1c3d7e902'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('consented_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('consent_version', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'consent_version')
    op.drop_column('users', 'consented_at')
