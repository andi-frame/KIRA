"""home blood pressure protocol

Revision ID: a3c5e7f9b061
Revises: f2b4d6e8a95a
Create Date: 2026-10-15 21:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'a3c5e7f9b061'
down_revision: Union[str, Sequence[str], None] = 'f2b4d6e8a95a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'bp_protocols',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('started_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('status', sa.Text(), server_default='active', nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('avg_sys', sa.Float(), nullable=True),
        sa.Column('avg_dia', sa.Float(), nullable=True),
        sa.Column('readings_used', sa.Integer(), nullable=True),
        sa.Column('result_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['result_id'], ['clinical_results.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ux_bp_protocols_one_active', 'bp_protocols', ['user_id'], unique=True, postgresql_where=sa.text("status = 'active'"))
    op.create_table(
        'bp_readings',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('protocol_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('measured_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('sys', sa.Integer(), nullable=False),
        sa.Column('dia', sa.Integer(), nullable=False),
        sa.Column('session', sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(['protocol_id'], ['bp_protocols.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_bp_readings_protocol', 'bp_readings', ['protocol_id', 'measured_at'])


def downgrade() -> None:
    op.drop_index('ix_bp_readings_protocol', table_name='bp_readings')
    op.drop_table('bp_readings')
    op.drop_index('ux_bp_protocols_one_active', table_name='bp_protocols')
    op.drop_table('bp_protocols')
