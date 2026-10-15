"""follow-up fields for check recommendations

Revision ID: d0f2b4c6e738
Revises: c9e1a3b5d627
Create Date: 2026-10-15 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'd0f2b4c6e738'
down_revision: Union[str, Sequence[str], None] = 'c9e1a3b5d627'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('check_recommendations', sa.Column('snoozed_until', sa.DateTime(timezone=True), nullable=True))
    op.add_column('check_recommendations', sa.Column('followups_sent', sa.Integer(), server_default='0', nullable=False))
    op.add_column('check_recommendations', sa.Column('last_followup_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('check_recommendations', 'last_followup_at')
    op.drop_column('check_recommendations', 'followups_sent')
    op.drop_column('check_recommendations', 'snoozed_until')
