"""saved what-if scenarios

Revision ID: b4d6f8a0c172
Revises: a3c5e7f9b061
Create Date: 2026-10-15 22:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'b4d6f8a0c172'
down_revision: Union[str, Sequence[str], None] = 'a3c5e7f9b061'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'whatif_scenarios',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('name', sa.Text(), nullable=False),
        sa.Column('params', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('saved_before', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('saved_after', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_whatif_scenarios_user', 'whatif_scenarios', ['user_id', sa.text('created_at DESC')])


def downgrade() -> None:
    op.drop_index('ix_whatif_scenarios_user', table_name='whatif_scenarios')
    op.drop_table('whatif_scenarios')
